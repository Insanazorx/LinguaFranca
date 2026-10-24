import Foundation
import Darwin
import LinguaFrancaCore
import LinguaFrancaInference

private struct Run: Codable {
    let topic: String
    let requestedLevel: String
    let requestedWordCount: Int
    let englishText: String
    let wordCount: Int
    let tokenCount: Int
    let seconds: Double
    let seed: UInt32
    let metadata: [String: String]
}

@main struct ModelSmoke {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let path = arguments.first, !path.hasPrefix("--") else {
            print("Usage: swift run model-smoke /absolute/model.gguf [--suite | --session-check] [--output /absolute/report.json]")
            return
        }
        if arguments.contains("--aggressive-check") {
            try await checkAggressive(path:path,arguments:arguments)
            return
        }
        if arguments.contains("--sense-check") { try await checkSenses(path:path,arguments:arguments); return }
        let sessionCheck = arguments.contains("--session-check")
        if arguments.contains("--vocabulary-check") {
            try await checkVocabulary(path: path, arguments: arguments)
            return
        }
        if arguments.contains("--genre-check") {
            try await checkGenres(path: path, arguments: arguments)
            return
        }
        let requests: [GenerationRequest] = sessionCheck ? [
            GenerationRequest(topic: "Education", seed: 42), GenerationRequest(topic: "Education", seed: 43)
        ] : arguments.contains("--suite") ? [
            GenerationRequest(topic: "daily life", level: .b2, seed: 42),
            GenerationRequest(topic: "technology", level: .c1, seed: 43),
            GenerationRequest(topic: "travel", level: .c1, seed: 44)
        ] : [GenerationRequest(topic: "daily life", seed: 42)]
        let service = LlamaCppService(modelURL: URL(fileURLWithPath: path))
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let planner = sessionCheck ? try GenerationVocabularyPlanner(registry: LanguagePackRegistry(directory: root.appendingPathComponent("Resources/LanguagePacks"))) : nil
        var session = ReadingSession()
        var runs: [Run] = []
        do {
            for var request in requests {
                if let planner {
                    request.targetLanguageCodes = ["de", "ru"]
                    request.vocabularyHints = try await planner.hints(topic: request.topic, settings: AppSettings(), seed: request.seed)
                    request.scenario = try session.nextScenario(seed: request.seed)
                    request.previousPassages = session.fingerprints
                }
                let result = try await service.generate(request: request)
                if sessionCheck {
                    try session.append(GeneratedText(originalEnglish: result.englishText, topic: request.topic,
                        cefrLevel: request.level, modelID: result.modelIdentifier, seed: result.seed, metadata: result.metadata))
                }
                let words = result.englishText.split(whereSeparator: \.isWhitespace).count
                runs.append(Run(topic: request.topic, requestedLevel: request.level.rawValue,
                    requestedWordCount: request.wordCount, englishText: result.englishText, wordCount: words,
                    tokenCount: result.tokenCount, seconds: result.duration, seed: result.seed, metadata: result.metadata))
                print("\n\(request.level.rawValue) · \(request.topic) · \(words) words · \(String(format: "%.2f", result.duration)) seconds (Mac host)")
                print(result.englishText)
            }
            await service.unloadModel()
            if let index = arguments.firstIndex(of: "--output"), arguments.indices.contains(index + 1) {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(runs).write(to: URL(fileURLWithPath: arguments[index + 1]), options: .atomic)
            }
        } catch {
            await service.unloadModel()
            throw error
        }
    }

    static func checkVocabulary(path: String, arguments: [String]) async throws {
        let service = LlamaCppService(modelURL: URL(fileURLWithPath: path))
        var records: [[String:Any]] = []
        for (index, code) in ["de","ru"].enumerated() {
            let targets = code == "de" ? ["Garten","Buch","Freund","Hoffnung","Abend","Weg"] : ["сад","книга","друг","надежда","вечер","путь"]
            let meanings = ["garden","book","friend","hope","evening","path"]
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let planner = VocabularyPracticePlanner(registry: try LanguagePackRegistry(directory: root.appendingPathComponent("Resources/LanguagePacks")))
            let items = zip(targets,meanings).enumerated().map {
                VocabularyItem(id:String($0.offset), draft:.init(englishLemma:$0.element.1,targetLanguage:code,targetLemma:$0.element.0,targetSurface:$0.element.0,senseID:$0.element.1,partOfSpeech:"noun"), createdAt:.now)
            }
            let batches = try await planner.batches(items:items,languageCode:code)
            for (batchIndex,practice) in batches.enumerated() {
                do {
                    let result = try await service.generate(request: GenerationRequest(topic: "Practice", wordCount: 90, seed: UInt32(120+index*10+batchIndex), vocabularyPractice: practice))
                    records.append(["language":code,"batch":batchIndex,"status":"passed","requiredExpressions":practice.expressions.map(\.target),"text":result.englishText,"metadata":result.metadata,"tokens":result.tokenCount,"seconds":result.duration])
                    print("Vocabulary \(code) batch \(batchIndex): passed\n\(result.englishText)")
                } catch {
                    records.append(["language":code,"batch":batchIndex,"status":"failed","error":error.localizedDescription])
                    print("Vocabulary \(code) batch \(batchIndex): \(error.localizedDescription)")
                }
            }
        }
        await service.unloadModel()
        if let flag = arguments.firstIndex(of: "--output"), arguments.indices.contains(flag+1) {
            try JSONSerialization.data(withJSONObject: records, options:[.prettyPrinted,.sortedKeys]).write(to: URL(fileURLWithPath:arguments[flag+1]), options:.atomic)
        }
        guard records.allSatisfy({ $0["status"] as? String == "passed" }) else { throw GenerationError.invalidOutput("vocabulary smoke check failed") }
    }

    static func checkGenres(path: String, arguments: [String]) async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let registry = try LanguagePackRegistry(directory: root.appendingPathComponent("Resources/LanguagePacks"))
        let planner = GenerationVocabularyPlanner(registry: registry), engine = ContextualReplacementEngine(registry: registry)
        let service = LlamaCppService(modelURL: URL(fileURLWithPath: path))
        var settings = AppSettings(); settings.replacementMode = .aggressive
        var session = ReadingSession(), records: [[String: Any]] = []
        for (index, genre) in WritingGenre.allCases.enumerated() {
            if let flag = arguments.firstIndex(of: "--only-genre"), arguments.indices.contains(flag + 1), arguments[flag + 1] != genre.rawValue { continue }
            let seed = UInt32(72 + index)
            do {
                let request = GenerationRequest(topic: "Daily life", seed: seed, targetLanguageCodes: ["de","ru"],
                    vocabularyHints: try await planner.hints(topic: "Daily life", settings: settings, seed: seed),
                    scenario: try session.nextScenario(seed: seed), previousPassages: session.fingerprints, genre: genre)
                let result = try await service.generate(request: request)
                let mixed = try await engine.replace(text: result.englishText, sourceTextID: genre.rawValue, settings: settings, seed: seed)
                try session.append(GeneratedText(originalEnglish: result.englishText, topic: "Daily life", cefrLevel: .c1, modelID: result.modelIdentifier, seed: seed))
                var record: [String: Any] = ["genre":genre.rawValue,"status":"passed","text":result.englishText,"words":result.englishText.split(whereSeparator: \.isWhitespace).count,"metadata":result.metadata,"replacements":mixed.spans.count,"eligible":mixed.eligibleWordCount]
                record["partsOfSpeech"] = Dictionary(grouping: mixed.spans, by: \.originalPartOfSpeech).mapValues(\.count)
                records.append(record)
                print("Genre \(genre.rawValue): passed, \(mixed.spans.count) replacements")
            } catch {
                records.append(["genre":genre.rawValue,"status":"failed","error":error.localizedDescription])
                print("Genre \(genre.rawValue): \(error.localizedDescription)")
            }
        }
        await service.unloadModel()
        if let flag = arguments.firstIndex(of: "--output"), arguments.indices.contains(flag + 1) {
            try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted,.sortedKeys]).write(to: URL(fileURLWithPath: arguments[flag + 1]), options: .atomic)
        }
    }
}
