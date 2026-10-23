import Foundation
import SwiftUI
import Observation
import UIKit
import LinguaFrancaCore
import LinguaFrancaInference

@MainActor @Observable final class AppEnvironment {
    private(set) var database: DatabaseManager?
    private(set) var decks: [StudyDeck] = []
    private(set) var vocabulary: [VocabularyItem] = []
    private(set) var passages: [GeneratedText] = []
    private(set) var settings = AppSettings()
    private(set) var summary: StudySummary?
    private(set) var generating = false
    private(set) var loading = true
    private(set) var storageBytes: Int64 = 0
    private(set) var passageCount = 0
    private(set) var languagePacks: [LanguagePackMetadata] = []
    private(set) var remixing = false
    var errorMessage: String?
    private var generationTask: Task<Void, Never>?
    private var refreshID = 0
    let modelURL: URL?
    let modelDisplayName = BundledModel.qwen35.identifier
    let availableTopics = ["Random", "Daily life", "Work and careers", "Technology", "Science", "Psychology", "Society", "Travel", "Literature", "Education", "Culture"]
    private let generator: LlamaCppService
    private var replacementEngine: ContextualReplacementEngine?
    var canGenerate: Bool { modelURL != nil }

    init() {
        let name = (BundledModel.qwen35.filename as NSString).deletingPathExtension
        let url = Bundle.main.url(forResource: name, withExtension: "gguf", subdirectory: "Models")
        modelURL = url
        generator = LlamaCppService(modelURL: url)
    }

    func open() async {
        guard database == nil else { return }
        loading = true
        do {
            // Keep existing user lists/settings when upgrading the former preview bundle to real inference.
            let folderName = Bundle.main.bundleIdentifier?.hasSuffix(".preview") == true ? "LinguaFrancaPreview" : "LinguaFranca"
            database = try await Task.detached(priority: .userInitiated) {
                let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: true)
                let folder = base.appendingPathComponent(folderName, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
                let database = try DatabaseManager(path: folder.appendingPathComponent("library.sqlite").path)
                _ = try await database.removeSamplePassages()
                return database
            }.value
            try await refresh()
            if let directory = Bundle.main.url(forResource: "LanguagePacks", withExtension: nil) {
                let registry = try await Task.detached(priority: .userInitiated) {
                    try LanguagePackRegistry(directory: directory)
                }.value
                languagePacks = registry.packs.map(\.metadata)
                replacementEngine = ContextualReplacementEngine(registry: registry)
            } else { throw DomainError.invalidInput("The bundled language packs are missing.") }
        } catch { errorMessage = error.localizedDescription }
        loading = false
    }

    func refresh() async throws {
        guard let database else { return }
        refreshID += 1
        let id = refreshID
        async let fetchedDecks = database.decks()
        async let fetchedWords = database.vocabulary()
        async let fetchedPassages = database.recentPassages()
        async let fetchedSettings = database.settings()
        async let fetchedSummary = database.studySummary()
        async let fetchedBytes = database.storageBytes()
        async let fetchedCount = database.passageCount()
        let result = try await (fetchedDecks, fetchedWords, fetchedPassages, fetchedSettings, fetchedSummary, fetchedBytes, fetchedCount)
        guard id == refreshID else { return }
        (decks, vocabulary, passages, settings, summary, storageBytes, passageCount) = result
    }

    func perform(_ operation: (DatabaseManager) async throws -> Void) async {
        guard let database else { errorMessage = "Your library is unavailable. Reopen the app to try again."; return }
        do { try await operation(database); try await refresh() }
        catch { errorMessage = error.localizedDescription }
    }

    func updateSettings(_ value: AppSettings) async throws {
        guard let database else { throw DomainError.missingRecord }
        try await database.saveSettings(value)
        settings = value
    }

    func generate(topic: String) {
        guard !generating, canGenerate, let database else { return }
        generating = true
        let generator = generator, current = settings, engine = replacementEngine
        generationTask = Task {
            defer { generating = false; generationTask = nil }
            do {
                let request = GenerationRequest(topic: topic, level: current.generationLevel,
                    wordCount: current.defaultWordCount, seed: .random(in: 0..<UInt32.max))
                let result = try await generator.generate(request: request)
                try Task.checkCancellation()
                var metadata = result.metadata
                metadata["durationSeconds"] = String(result.duration)
                metadata["tokenCount"] = String(result.tokenCount)
                let id = UUID().uuidString
                let mix = try await engine?.replace(text: result.englishText, sourceTextID: id, settings: current, seed: result.seed)
                Self.addReplacementMetadata(mix, to: &metadata)
                let passage = GeneratedText(id: id, originalEnglish: result.englishText, topic: topic, cefrLevel: request.level,
                    modelID: result.modelIdentifier, seed: result.seed, metadata: metadata, replacements: mix?.spans ?? [])
                try await database.savePassage(passage)
                try await refresh()
            } catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func cancelGeneration() { generationTask?.cancel() }
    func remix(_ passage: GeneratedText) async {
        guard !remixing, let engine = replacementEngine, let database else { return }
        remixing = true
        defer { remixing = false }
        do {
            let mix = try await engine.replace(text: passage.originalEnglish, sourceTextID: passage.id, settings: settings, seed: passage.seed)
            var metadata = passage.metadata
            Self.addReplacementMetadata(mix, to: &metadata)
            let updated = GeneratedText(id: passage.id, originalEnglish: passage.originalEnglish, topic: passage.topic,
                cefrLevel: passage.cefrLevel, generatedAt: passage.generatedAt, modelID: passage.modelID,
                seed: passage.seed, metadata: metadata, replacements: mix.spans)
            try await database.savePassage(updated)
            try await refresh()
        } catch { errorMessage = error.localizedDescription }
    }
    private static func addReplacementMetadata(_ result: ReplacementResult?, to metadata: inout [String:String]) {
        metadata["replacementStatus"] = result == nil ? "language-packs-unavailable" : "local-lexicon"
        metadata["requestedDensity"] = String(result?.requestedDensity ?? 0)
        metadata["actualDensity"] = String(result?.actualDensity ?? 0)
        metadata["replacementWordCount"] = String(result?.wordCount ?? 0)
        metadata["replacementCount"] = String(result?.spans.count ?? 0)
        metadata["replacementEngineVersion"] = "contextual-3"
        for key in metadata.keys.filter({ $0.hasPrefix("replacementCount.") }) { metadata.removeValue(forKey:key) }
        for (code, count) in result?.languageCounts ?? [:] { metadata["replacementCount.\(code)"] = String(count) }
    }
    func releaseModel() async {
        generationTask?.cancel()
        await generator.unloadModel()
    }
}
