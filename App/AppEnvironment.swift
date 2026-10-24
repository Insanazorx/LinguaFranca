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
    private(set) var readingSession = ReadingSession()
    var passages: [GeneratedText] { readingSession.visiblePassages }
    var passageCount: Int { passages.count }
    private(set) var settings = AppSettings()
    private(set) var summary: StudySummary?
    private(set) var generating = false
    private(set) var loading = true
    private(set) var storageBytes: Int64 = 0
    private(set) var languagePacks: [LanguagePackMetadata] = []
    private(set) var remixing = false
    private(set) var vocabularyReadings: [VocabularyPracticeReading] = []
    private(set) var activeVocabularyGroup: String?
    private(set) var vocabularyBatchProgress = 0
    private(set) var vocabularyBatchTotal = 0
    var errorMessage: String?
    private(set) var generationMessage: String?
    private(set) var generationPhase = ""
    private var generationTask: Task<Void, Never>?
    private var refreshID = 0
    let modelURL: URL?
    let modelDisplayName = BundledModel.qwen35.identifier
    let availableTopics = ["Random", "Daily life", "Work and careers", "Technology", "Science", "Psychology", "Society", "Travel", "Literature", "Education", "Culture"]
    private let generator: LlamaCppService
    private var replacementEngine: ContextualReplacementEngine?
    private var vocabularyPlanner: GenerationVocabularyPlanner?
    private var practicePlanner: VocabularyPracticePlanner?
    var canGenerate: Bool { modelURL != nil && replacementEngine != nil && !loading }

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
                return database
            }.value
            try await refresh()
            if let directory = Bundle.main.url(forResource: "LanguagePacks", withExtension: nil) {
                let registry = try await Task.detached(priority: .userInitiated) {
                    try LanguagePackRegistry(directory: directory)
                }.value
                languagePacks = registry.packs.map(\.metadata)
                replacementEngine = ContextualReplacementEngine(registry: registry, senseSelector: generator)
                vocabularyPlanner = GenerationVocabularyPlanner(registry: registry)
                practicePlanner = VocabularyPracticePlanner(registry: registry)
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
        async let fetchedSettings = database.settings()
        async let fetchedSummary = database.studySummary()
        async let fetchedBytes = database.storageBytes()
        let result = try await (fetchedDecks, fetchedWords, fetchedSettings, fetchedSummary, fetchedBytes)
        guard id == refreshID else { return }
        (decks, vocabulary, settings, summary, storageBytes) = result
    }

    func perform(_ operation: (DatabaseManager) async throws -> Void) async {
        guard let database else { errorMessage = "Your library is unavailable. Reopen the app to try again."; return }
        do { try await operation(database); try await refresh() }
        catch { errorMessage = error.localizedDescription }
    }

    func updateSettings(_ value: AppSettings) async throws {
        guard let database else { throw DomainError.missingRecord }
        let previous = settings
        settings = value
        do { try await database.saveSettings(value) }
        catch { if settings == value { settings = previous }; throw error }
    }

    func generate(topic: String) {
        guard !generating else { return }
        guard canGenerate, database != nil else { errorMessage = "The local model and language packs are not ready. Reopen the app and try again."; return }
        generating = true; generationMessage = nil; generationPhase = "Writing on your device…"
        let generator = generator, current = settings, engine = replacementEngine, planner = vocabularyPlanner
        generationTask = Task {
            defer { generating = false; generationTask = nil }
            let groupID = UUID().uuidString
            var avoid: Set<String> = []
            let limit = current.replacementMode == .aggressive ? 3 : 1
            do {
                for attempt in 0..<limit {
                    try Task.checkCancellation()
                    generationPhase = attempt == 0 ? "Writing on your device…" : "Preparing a fully translated reading (\(attempt+1)/\(limit))…"
                    let seed = UInt32.random(in: 0..<UInt32.max)
                    let scenario = try readingSession.nextScenario(seed: seed)
                    let hints = try await planner?.hints(topic: topic, settings: current, seed: seed) ?? []
                    let request = GenerationRequest(topic: topic, level: current.generationLevel,
                        wordCount: current.defaultWordCount, seed: seed,
                        targetLanguageCodes: current.replacementLanguageShares.filter { $0.value > 0 }.keys.sorted(),
                        vocabularyHints: hints, scenario: scenario, previousPassages: readingSession.fingerprints, genre: current.writingGenre,
                        aggressiveDomains: current.replacementMode == .aggressive ? current.practiceDomains : [], avoidWords: avoid.sorted())
                    let result = try await generator.generate(request: request)
                    try Task.checkCancellation()
                    var metadata = result.metadata
                    metadata["durationSeconds"] = String(result.duration); metadata["tokenCount"] = String(result.tokenCount)
                    metadata["generationGroupID"] = groupID; metadata["replacementStatus"] = "processing"
                    Self.addFocusMetadata(current,to:&metadata)
                    let id = UUID().uuidString
                    let source = GeneratedText(id:id,originalEnglish:result.englishText,topic:topic,cefrLevel:request.level,
                        modelID:result.modelIdentifier,seed:result.seed,metadata:metadata)
                    try readingSession.append(source)
                    generationPhase = "Preparing translations…"
                    do {
                        guard let engine else { throw DomainError.invalidInput("The local language packs are unavailable.") }
                        let mix = try await engine.replace(text:source.originalEnglish,sourceTextID:id,settings:current,seed:result.seed)
                        try Task.checkCancellation()
                        Self.addReplacementMetadata(mix,to:&metadata)
                        let complete = current.replacementMode != .aggressive || mix.isComplete
                        metadata["replacementComplete"] = String(complete)
                        // An incomplete Aggressive draft is never presented as a finished mixed text.
                        let ready = GeneratedText(id:id,originalEnglish:source.originalEnglish,topic:topic,cefrLevel:request.level,
                            generatedAt:source.generatedAt,modelID:result.modelIdentifier,seed:result.seed,metadata:metadata,replacements:complete ? mix.spans : [])
                        try readingSession.remix(ready)
                        if complete { generationMessage = nil; return }
                        avoid.formUnion(mix.unresolved.map { $0.contextExpression ?? $0.surface })
                        generationMessage = "Aggressive translation is incomplete. Finding a reading where every selected component can be translated correctly…"
                    } catch is CancellationError {
                        metadata["replacementStatus"] = "cancelled"; metadata["replacementComplete"] = "false"
                        try? readingSession.remix(GeneratedText(id:id,originalEnglish:source.originalEnglish,topic:topic,cefrLevel:source.cefrLevel,
                            generatedAt:source.generatedAt,modelID:source.modelID,seed:source.seed,metadata:metadata))
                        generationMessage = "Translation stopped. Your generated text is still available below."; return
                    } catch {
                        metadata["replacementStatus"] = "failed"; metadata["replacementComplete"] = "false"
                        try? readingSession.remix(GeneratedText(id:id,originalEnglish:source.originalEnglish,topic:topic,cefrLevel:source.cefrLevel,
                            generatedAt:source.generatedAt,modelID:source.modelID,seed:source.seed,metadata:metadata))
                        generationMessage = "Your text is ready. Translation could not finish: " + error.localizedDescription; return
                    }
                }
                generationMessage = "A fully verified Aggressive translation could not be completed. The English text is kept below; no uncertain translation was forced. Try another generation or selection."
            } catch is CancellationError { generationMessage = "Generation stopped. Any completed text is still available below." }
            catch { generationMessage = error.localizedDescription; if passages.isEmpty { errorMessage = error.localizedDescription } }
        }
    }

    func cancelGeneration() { generationTask?.cancel() }
    func generateVocabulary(items: [VocabularyItem], languageCode: String, groupID: String) {
        guard !generating, canGenerate else { return }
        generating = true; activeVocabularyGroup = groupID
        vocabularyBatchProgress = 0; vocabularyBatchTotal = 0
        generationTask = Task {
            defer { generating = false; activeVocabularyGroup = nil; generationTask = nil }
            do {
                let batches: [VocabularyPracticeRequest]
                if let practicePlanner { batches = try await practicePlanner.batches(items: items, languageCode: languageCode) }
                else { batches = try VocabularyPracticeRequest.batches(items: items, languageCode: languageCode) }
                vocabularyBatchTotal = batches.count
                vocabularyReadings.removeAll { $0.groupID == groupID }
                for batch in batches {
                    try Task.checkCancellation()
                    let seed = UInt32.random(in: 0..<UInt32.max)
                    let scene = try readingSession.nextScenario(seed: seed)
                    let request = GenerationRequest(topic: "Vocabulary practice", level: settings.generationLevel,
                        wordCount: 90, seed: seed, scenario: scene,
                        previousPassages: vocabularyReadings.filter { $0.languageCode == languageCode }.map { PassageFingerprint($0.text) }, vocabularyPractice: batch)
                    let result = try await generator.generate(request: request)
                    try Task.checkCancellation()
                    vocabularyReadings.append(.init(groupID: groupID, languageCode: languageCode,
                        text: result.englishText, expressionIDs: batch.expressions.map(\.id)))
                    vocabularyBatchProgress += 1
                }
            } catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }
    func remix(_ passage: GeneratedText) async {
        guard !remixing, let engine = replacementEngine else { return }
        remixing = true
        defer { remixing = false }
        do {
            let mix = try await engine.replace(text: passage.originalEnglish, sourceTextID: passage.id, settings: settings, seed: passage.seed)
            var metadata = passage.metadata
            Self.addReplacementMetadata(mix, to: &metadata)
            Self.addFocusMetadata(settings, to: &metadata)
            let updated = GeneratedText(id: passage.id, originalEnglish: passage.originalEnglish, topic: passage.topic,
                cefrLevel: passage.cefrLevel, generatedAt: passage.generatedAt, modelID: passage.modelID,
                seed: passage.seed, metadata: metadata, replacements: settings.replacementMode == .aggressive && !mix.isComplete ? [] : mix.spans)
            try Task.checkCancellation()
            try readingSession.remix(updated)
            if settings.replacementMode == .aggressive, !mix.isComplete {
                generationMessage = "Aggressive translation is incomplete: " + mix.unresolved.map(\.surface).joined(separator:", ") + ". Generate a new reading for this selection."
            } else { generationMessage = nil }
        } catch { errorMessage = error.localizedDescription }
    }
    private static func addReplacementMetadata(_ result: ReplacementResult?, to metadata: inout [String:String]) {
        metadata["eligibleWordCount"] = String(result?.eligibleWordCount ?? 0)
        metadata["replacementStatus"] = result == nil ? "language-packs-unavailable" : "local-lexicon"
        metadata["requestedDensity"] = String(result?.requestedDensity ?? 0)
        metadata["actualDensity"] = String(result?.actualDensity ?? 0)
        metadata["replacementWordCount"] = String(result?.wordCount ?? 0)
        metadata["replacementCount"] = String(result?.spans.count ?? 0)
        metadata["replacedWordCount"] = String(result?.replacedWordCount ?? 0)
        metadata["replacementEngineVersion"] = "contextual-7-complete"
        metadata["replacementComplete"] = String(result?.isComplete ?? false)
        metadata["unresolvedWordCount"] = String(result?.unresolved.count ?? 0)
        metadata["unresolvedWords"] = result?.unresolved.map(\.surface).joined(separator:" · ") ?? ""
        for key in metadata.keys.filter({ $0.hasPrefix("replacementCount.") }) { metadata.removeValue(forKey:key) }
        for (code, count) in result?.languageCounts ?? [:] { metadata["replacementCount.\(code)"] = String(count) }
    }
    private static func addFocusMetadata(_ settings: AppSettings, to metadata: inout [String:String]) {
        metadata["replacementMode"] = settings.replacementMode.rawValue
        metadata["practiceDomains"] = settings.practiceDomains.map(\.rawValue).sorted().joined(separator: ",")
    }
    func releaseModel() async {
        generationTask?.cancel()
        await generator.unloadModel()
    }
}
