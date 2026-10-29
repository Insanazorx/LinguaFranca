import Foundation
import LinguaFrancaCore
import LinguaFrancaInference

extension ModelSmoke {
    /// Real local-model integration checks; not a CEFR or semantic certification.
    static func checkFormats(path: String, arguments: [String]) async throws {
        let aggressive = arguments.contains("--aggressive-formats")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let registry = try LanguagePackRegistry(directory: root.appendingPathComponent("Resources/LanguagePacks"))
        let model = LlamaCppService(modelURL: URL(fileURLWithPath: path), model: aggressive ? .aggressive : .qwen35)
        let engine = ContextualReplacementEngine(registry: registry)
        let direct = AggressiveReadingGenerator(model: model, registry: registry)
        var settings = AppSettings(); settings.generationLevel = .nichijou
        settings.replacementMode = aggressive ? .aggressive : .balanced
        settings.practiceDomains = [.structure]; settings.enabledLanguages = ["de", "ru"]
        var session = ReadingSession(), rows: [[String: Any]] = []
        for (index, genre) in [WritingGenre.dialogue, .play, .poem].enumerated() {
            if let flag = arguments.firstIndex(of: "--only-genre"), arguments.indices.contains(flag + 1), arguments[flag + 1] != genre.rawValue { continue }
            do {
                let seed = UInt32(324 + index)
                let request = GenerationRequest(topic: "Daily life", level: .nichijou, seed: seed,
                    targetLanguageCodes: settings.enabledLanguages, scenario: try session.nextScenario(seed: seed),
                    previousPassages: session.fingerprints, genre: genre)
                let reading: GeneratedText
                if aggressive { reading = try await direct.generate(request: request, settings: settings) }
                else {
                    let result = try await model.generate(request: request)
                    let id = UUID().uuidString
                    let replacements = try await engine.replace(text: result.englishText, sourceTextID: id, settings: settings, seed: seed)
                    reading = .init(id: id, originalEnglish: result.englishText, topic: request.topic, cefrLevel: request.level,
                        modelID: result.modelIdentifier, seed: result.seed, metadata: result.metadata, replacements: replacements.spans)
                }
                _ = try PassageValidator.validate(reading.originalEnglish, requestedWords: 110, genre: genre)
                try session.append(reading)
                rows.append(["genre": genre.rawValue, "mode": settings.replacementMode.rawValue, "level": "Nichijou", "status": "passed", "original": reading.originalEnglish, "rendered": try reading.renderedText(), "replacements": reading.replacements.count, "metadata": reading.metadata])
                print("FORMAT \(genre.rawValue): passed\n\(reading.originalEnglish)")
            } catch {
                rows.append(["genre": genre.rawValue, "status": "failed", "error": error.localizedDescription])
                print("FORMAT \(genre.rawValue): failed: \(error.localizedDescription)")
            }
        }
        await model.unloadModel()
        if let flag = arguments.firstIndex(of: "--output"), arguments.indices.contains(flag + 1) {
            try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: arguments[flag + 1]), options: .atomic)
        }
        guard rows.allSatisfy({ $0["status"] as? String == "passed" }) else { throw GenerationError.invalidOutput("format integration check failed") }
    }
}
