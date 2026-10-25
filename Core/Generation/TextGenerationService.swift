import Foundation
import NaturalLanguage

public struct GenerationConfiguration: Codable, Sendable, Equatable {
    public var contextWindow: Int = 2048
    public var maximumTokens: Int = 320
    public var temperature: Float = 0.7
    public var topP: Float = 0.9
    public var repetitionPenalty: Float = 1.05
    public var batchSize: Int = 64
    public init() {}
    public func validate() throws {
        guard (512...4096).contains(contextWindow), (64...1536).contains(maximumTokens),
              maximumTokens < contextWindow, [32, 64].contains(batchSize),
              temperature.isFinite, (0...2).contains(temperature), topP.isFinite, (0.01...1).contains(topP),
              repetitionPenalty.isFinite, (1...2).contains(repetitionPenalty)
        else { throw DomainError.invalidInput("The model configuration exceeds its validated bounds.") }
    }
}

public struct GenerationRequest: Sendable, Equatable {
    public var topic: String
    public var level: CEFRLevel
    public var wordCount: Int
    public var seed: UInt32
    public var style: String?
    public var genre: WritingGenre
    public var configuration: GenerationConfiguration
    public var targetLanguageCodes: [String]
    public var vocabularyHints: [GenerationVocabularyHint]
    public var scenario: GenerationScenario?
    /// Used only after inference. Previous prose is never included in the model prompt.
    public var previousPassages: [PassageFingerprint]
    public var vocabularyPractice: VocabularyPracticeRequest?
    public var aggressiveDomains: Set<PracticeDomain>
    public var avoidWords: [String]
    public var senseSelection: ContextualSenseRequest?
    public var aggressiveTask: AggressiveModelTask? = nil
    public var readingTranslation: ReadingTranslationTask? = nil
    public init(topic: String, level: CEFRLevel = .c1, wordCount: Int = 110,
                seed: UInt32, style: String? = nil, configuration: GenerationConfiguration = .init(),
                targetLanguageCodes: [String] = [], vocabularyHints: [GenerationVocabularyHint] = [],
                scenario: GenerationScenario? = nil, previousPassages: [PassageFingerprint] = [], genre: WritingGenre = .story,
                vocabularyPractice: VocabularyPracticeRequest? = nil, aggressiveDomains: Set<PracticeDomain> = [], avoidWords: [String] = [], senseSelection: ContextualSenseRequest? = nil) {
        self.topic = topic; self.level = level; self.wordCount = wordCount
        self.seed = seed; self.style = style; self.configuration = configuration
        self.targetLanguageCodes = targetLanguageCodes; self.vocabularyHints = vocabularyHints
        self.scenario = scenario; self.previousPassages = previousPassages
        self.genre = genre
        self.vocabularyPractice = vocabularyPractice
        self.aggressiveDomains = aggressiveDomains; self.avoidWords = avoidWords
        self.senseSelection = senseSelection
    }
    public func validate() throws {
        try configuration.validate()
        try vocabularyPractice?.validate()
        try senseSelection?.validate()
        try readingTranslation?.validate()
        if readingTranslation != nil && (aggressiveTask != nil || senseSelection != nil || vocabularyPractice != nil) {
            throw DomainError.invalidInput("Reading translation must be an independent model task.")
        }
        guard (90...150).contains(wordCount), !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              topic.count <= 100, (style?.count ?? 0) <= 100,
              !topic.contains("<|"), !(style?.contains("<|") ?? false)
        else { throw DomainError.invalidInput("Choose a topic and a passage length between 90 and 150 words.") }
        guard targetLanguageCodes.count <= 16, vocabularyHints.count <= 48,
              targetLanguageCodes.allSatisfy({ (2...3).contains($0.count) && $0.allSatisfy({ $0.isASCII && $0.isLowercase && $0.isLetter }) }),
              vocabularyHints.allSatisfy({ targetLanguageCodes.contains($0.languageCode) && (1...40).contains($0.englishLemma.count)
                  && $0.englishLemma.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == " " || $0 == "-") }) })
        else { throw DomainError.invalidInput("Invalid local vocabulary guidance.") }
    }
    public var prompt: String {
        if let readingTranslation { return readingTranslation.prompt }
        if let aggressiveTask {
            return aggressiveTask.instructions + (aggressiveTask.repair == nil ? "Topic: \(topic). \(genre.instruction) CEFR \(level.rawValue). \(scenarioGuidance) Naturally include these English concepts if provided: \(vocabularyHints.map(\.englishLemma).joined(separator:", "))." : "")
        }
        if let senseSelection { return senseSelection.prompt }
        if let vocabularyPractice { return vocabularyPractice.prompt + (scenario.map { vocabularyPractice.sceneGuidance($0.id) } ?? "") }
        return genre.instruction + " "
        + "Write a complete text in English. Choose a length that suits the scene. "
        + "Topic: \(topic). Keep this topic central, even when adapting the scene below. "
        + "Use natural CEFR \(level.rawValue) English, specific details and a clear ending. "
        + (style.map { "Style: \($0). " } ?? "")
        + scenarioGuidance
        + vocabularyGuidance
        + aggressiveGuidance
        + "Finish the passage. Output only the passage, without title, Markdown, explanations or translations."
    }
    private var scenarioGuidance: String {
        guard let scenario else { return "" }
        switch genre {
        case .essay: return "Angle: \(scenario.focus), linked to the topic. "
        case .poem: return "Use imagery from \(scenario.situation). "
        case .dialogue, .play: return "Scene: \(scenario.situation). Conflict: \(scenario.focus). "
        case .story, .novel: return "New scene: \(scenario.situation). Focus: \(scenario.focus). Perspective: \(aggressiveDomains.contains(.actions) ? "third-person present tense" : scenario.perspective). "
        }
    }
    private var aggressiveGuidance: String {
        guard !aggressiveDomains.isEmpty else { return "" }
        var guidance = "EXTREME AGGRESSIVE PRACTICE: deliberately saturate the passage with the selected language features. Push their density conspicuously beyond ordinary prose, while keeping every clause grammatical and the meaning coherent. Apply ALL selected profiles together. "
        if aggressiveDomains.contains(.structure) {
            guidance += "CONNECTORS AND PREPOSITIONS: pack almost every sentence with several coordinating or subordinating conjunctions and several prepositional phrases. Chain reasons, contrasts, conditions and time clauses; stack clear location, direction, company and time phrases. Make the abundance unmistakable. "
        }
        if aggressiveDomains.contains(.actions) {
            guidance += "VERBS AND VERB FORMS: make almost every clause action-rich. Chain several distinct lexical verbs per sentence, use explicit subjects and mostly active present tense, and add suitable infinitives or sentence-initial participial phrases. Prefer concrete actions over vague auxiliary-only predicates. "
        }
        if aggressiveDomains.contains(.content) {
            guidance += "NOUNS, ADJECTIVES AND ADVERBS: make every sentence exceptionally rich in concrete nouns, precise predicative adjectives and varied meaningful adverbs. Use abundant descriptions of states and qualities as well as detailed objects. Make adjective descriptions clearly predicative, with explicit subjects. "
        }
        if aggressiveDomains.contains(.prepositionalPhrases) {
            guidance += "PREPOSITION COMPLEMENTS: use an unusually large number of complete preposition-plus-object or preposition-plus-activity phrases. Layer several clear complements in each sentence so that their relations and case roles are explicit. "
        }
        return guidance + (avoidWords.isEmpty ? "" : "Choose different expressions instead of: \(avoidWords.prefix(24).joined(separator:", ")). ")
    }
    private var vocabularyGuidance: String {
        guard !targetLanguageCodes.isEmpty else { return "" }
        let languages = targetLanguageCodes.sorted().map { Locale(identifier: "en").localizedString(forLanguageCode: $0) ?? $0 }.joined(separator: " and ")
        let words = Array(Set(vocabularyHints.map(\.englishLemma))).sorted().joined(separator: ", ")
        return "For later \(languages) practice, prefer concepts with distinct common equivalents in those languages. International words may appear naturally, but should not dominate. "
            + (words.isEmpty ? "" : "Naturally include a few of: \(words). ")
            + "Write entirely in English. "
    }
    /// Matches the bundled Qwen3.5 chat template with enable_thinking=false.
    public var chatPrompt: String {
        let instruction = readingTranslation != nil ? "You translate English faithfully into Russian. Return only the requested JSON. Never invent events or omit details." : aggressiveTask != nil ? "You are a precise multilingual language teacher. Return only the requested JSON. Keep the original English separate from all translations. Correct meaning, inflection and complete category coverage are essential." : senseSelection != nil ? "Classify the meaning of the marked English expression. Choose only an exactly applicable English definition; choose 0 for a literal combination that is not the listed idiom. Output only the option number." : vocabularyPractice?.systemInstruction
            ?? "You write \(genre.title.lowercased()) in English. Follow the requested literary format. Output only the requested text.\(aggressiveSystemInstruction)"
        return "<|im_start|>system\n\(instruction)<|im_end|>\n"
        + "<|im_start|>user\n\(prompt)<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
    }
    private var aggressiveSystemInstruction: String {
        guard !aggressiveDomains.isEmpty else { return "" }
        var rules = " This is an intensive grammar exercise. Set the entire scene NOW. Use third-person simple PRESENT with explicit he, she or they subjects."
        if aggressiveDomains.contains(.actions) { rules += " Every sentence contains several distinct concrete actions. Chain present-tense verbs and infinitives with clear subjects." }
        if aggressiveDomains.contains(.structure) { rules += " Every sentence contains MANY conjunctions and prepositions: stack time clauses, reasons, conditions, contrasts and concrete spatial relations. Use far more than ordinary writing." }
        if aggressiveDomains.contains(.content) { rules += " Every sentence contains MANY concrete nouns, predicative adjectives and precise adverbs. State qualities with clear subjects." }
        if aggressiveDomains.contains(.prepositionalPhrases) { rules += " Stack MANY complete preposition-plus-object phrases with concrete objects and clear spatial relations in every sentence." }
        return rules + " Keep the scene coherent. Start directly with the text."
    }
    public var outputGrammar: String? { readingTranslation?.grammar ?? aggressiveTask?.grammar ?? senseSelection?.grammar ?? (vocabularyPractice == nil ? genre.outputGrammar : vocabularyPractice?.outputGrammar) }
}

public struct GenerationResult: Sendable, Equatable {
    public let englishText: String
    public let duration: TimeInterval
    public let modelIdentifier: String
    public let seed: UInt32
    public let tokenCount: Int
    public let metadata: [String: String]
    public init(englishText: String, duration: TimeInterval, modelIdentifier: String, seed: UInt32,
                tokenCount: Int, metadata: [String: String]) {
        self.englishText = englishText; self.duration = duration; self.modelIdentifier = modelIdentifier
        self.seed = seed; self.tokenCount = tokenCount; self.metadata = metadata
    }
}

public protocol TextGenerationService: Sendable {
    func loadModel() async throws
    func generate(request: GenerationRequest) async throws -> GenerationResult
    func cancelGeneration() async
    func unloadModel() async
}

public enum GenerationError: Error, LocalizedError, Sendable, Equatable {
    case missingModel, checksumMismatch, invalidModel, contextFailure, decodeFailure, busy, invalidOutput(String)
    public var errorDescription: String? {
        switch self {
        case .missingModel: "The bundled language model is missing from this build."
        case .checksumMismatch: "The language model failed its integrity check."
        case .invalidModel: "The local model could not be loaded."
        case .contextFailure: "The local model could not allocate its reading context."
        case .decodeFailure: "Local text generation could not finish. Please try again."
        case .busy: "A passage is already being generated."
        case .invalidOutput(let reason): "The generated passage needs another attempt: \(reason)"
        }
    }
}

public enum PassageValidator {
    public static func validate(_ text: String, requestedWords: Int, genre: WritingGenre = .story) throws -> String {
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var wrapperLines = clean.components(separatedBy:.newlines)
        if wrapperLines.first?.hasPrefix("```") == true, wrapperLines.last?.hasPrefix("```") == true, wrapperLines.count > 2 {
            wrapperLines.removeFirst(); wrapperLines.removeLast()
        }
        if let first = wrapperLines.first, first.hasPrefix("#") { wrapperLines.removeFirst() }
        if let first = wrapperLines.first, ["here is","here's","sure,"].contains(where: { first.lowercased().hasPrefix($0) }),
           wrapperLines.count > 1 { wrapperLines.removeFirst() }
        clean = wrapperLines.joined(separator:"\n").trimmingCharacters(in:.whitespacesAndNewlines)
        let forbidden = ["<think", "</think", "<|", "```", "#", "**"]
        let commentary = ["As an AI", "Here is", "Here's", "Sure,"]
        guard !forbidden.contains(where: { clean.localizedCaseInsensitiveContains($0) }),
              !commentary.contains(where: { clean.lowercased().hasPrefix($0.lowercased()) }) else {
            throw GenerationError.invalidOutput("control tokens or commentary")
        }
        // Approximate length is guidance, never a reason to throw away valid prose.
        if genre != .poem, clean.last.map({ ".!?\"”)".contains($0) }) != true {
            let tokenizer = NLTokenizer(unit: .sentence); tokenizer.string = clean; tokenizer.setLanguage(.english)
            var end: String.Index?
            tokenizer.enumerateTokens(in: clean.startIndex..<clean.endIndex) { range, _ in
                if clean[range].trimmingCharacters(in: .whitespacesAndNewlines).last.map({ ".!?\"”)".contains($0) }) == true { end = range.upperBound }
                return true
            }
            guard let end else { throw GenerationError.invalidOutput("no completed sentence") }
            clean = String(clean[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let letters = clean.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let latin = letters.filter { $0.isASCII }
        let lines = clean.split(whereSeparator: \.isNewline)
        if [.dialogue, .play].contains(genre) {
            let turns = lines.filter { $0.range(of: #"^[\p{L}][\p{L} ’-]{0,30}:\s*\S"#, options: .regularExpression) != nil }
            guard turns.count >= 2 else { throw GenerationError.invalidOutput("missing speaker turns") }
        }
        if genre == .poem, lines.count < 4 { throw GenerationError.invalidOutput("missing poem line breaks") }
        guard !letters.isEmpty, Double(latin.count) / Double(letters.count) > 0.95,
              let last = clean.last, (genre == .poem ? last.isLetter || ".!?\"”".contains(last) : ".!?\"”)".contains(last)) else {
            throw GenerationError.invalidOutput("unfinished or non-English prose")
        }
        // This is a structural guard, not a CEFR quality or language certification.
        return clean
    }
}
