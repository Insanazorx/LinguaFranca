import Foundation

public struct GenerationConfiguration: Codable, Sendable, Equatable {
    public var contextWindow: Int = 2048
    public var maximumTokens: Int = 320
    public var temperature: Float = 0.7
    public var topP: Float = 0.9
    public var repetitionPenalty: Float = 1.05
    public var batchSize: Int = 64
    public init() {}
    public func validate() throws {
        guard (512...4096).contains(contextWindow), (64...320).contains(maximumTokens),
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
    public var configuration: GenerationConfiguration
    public init(topic: String, level: CEFRLevel = .c1, wordCount: Int = 110,
                seed: UInt32, style: String? = nil, configuration: GenerationConfiguration = .init()) {
        self.topic = topic; self.level = level; self.wordCount = wordCount
        self.seed = seed; self.style = style; self.configuration = configuration
    }
    public func validate() throws {
        try configuration.validate()
        guard (90...150).contains(wordCount), !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              topic.count <= 100, (style?.count ?? 0) <= 100,
              !topic.contains("<|"), !(style?.contains("<|") ?? false)
        else { throw DomainError.invalidInput("Choose a topic and a passage length between 90 and 150 words.") }
    }
    public var prompt: String {
        "Write one original English reading passage of approximately \(wordCount) words about \(topic). "
        + "Target CEFR \(level.rawValue) vocabulary and sentence complexity with natural grammar and varied transitions. "
        + "Describe a concrete situation with specific details and a clear beginning, development and ending. Avoid vague generalisations. "
        + (style.map { "Style: \($0). " } ?? "")
        + "Output only the passage, without title, Markdown, explanations or translations."
    }
    /// Matches the bundled Qwen3.5 chat template with enable_thinking=false.
    public var chatPrompt: String {
        "<|im_start|>system\nYou write coherent English reading passages for language learners.<|im_end|>\n"
        + "<|im_start|>user\n\(prompt)<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
    }
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
    public static func validate(_ text: String, requestedWords: Int) throws -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbidden = ["<think", "</think", "<|", "```", "#", "**"]
        let commentary = ["As an AI", "Here is", "Here's", "Sure,"]
        guard !forbidden.contains(where: { clean.localizedCaseInsensitiveContains($0) }),
              !commentary.contains(where: { clean.lowercased().hasPrefix($0.lowercased()) }) else {
            throw GenerationError.invalidOutput("control tokens or commentary")
        }
        let words = clean.split(whereSeparator: { $0.isWhitespace })
        guard words.count >= max(60, requestedWords * 2 / 3), words.count <= requestedWords * 3 / 2 else {
            throw GenerationError.invalidOutput("unexpected length")
        }
        let letters = clean.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let latin = letters.filter { $0.isASCII }
        guard !letters.isEmpty, Double(latin.count) / Double(letters.count) > 0.95,
              let last = clean.last, ".!?\"”".contains(last) else {
            throw GenerationError.invalidOutput("unfinished or non-English prose")
        }
        // This is a structural guard, not a CEFR quality or language certification.
        return clean
    }
}
