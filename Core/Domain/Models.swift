import Foundation

public enum CEFRLevel: String, Codable, CaseIterable, Sendable { case b2 = "B2", c1 = "C1" }
public enum ReplacementDensity: String, Codable, CaseIterable, Sendable {
    case low, medium, high, psycho
    public var target: Double { switch self { case .low: 0.1; case .medium: 0.2; case .high: 0.3; case .psycho: 0.5 } }
}

public enum DomainError: Error, LocalizedError, Sendable, Equatable {
    case invalidInput(String), missingRecord, duplicateVocabulary, invalidSpan
    public var errorDescription: String? {
        switch self {
        case .invalidInput(let message): message
        case .missingRecord: "This item no longer exists."
        case .duplicateVocabulary: "This expression and meaning are already saved."
        case .invalidSpan: "The replacement does not match the original passage."
        }
    }
}

public struct StudyDeck: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let createdAt: Date
    public let updatedAt: Date
    public let wordCount: Int
}

public struct VocabularyDraft: Sendable, Equatable {
    public var englishLemma: String
    public var targetLanguage: String
    public var targetLemma: String
    public var targetSurface: String
    public var senseID: String
    public var partOfSpeech: String
    public var exampleEnglish: String
    public var exampleMixed: String
    public init(englishLemma: String, targetLanguage: String, targetLemma: String,
                targetSurface: String, senseID: String, partOfSpeech: String = "unspecified",
                exampleEnglish: String = "", exampleMixed: String = "") {
        self.englishLemma = englishLemma; self.targetLanguage = targetLanguage
        self.targetLemma = targetLemma; self.targetSurface = targetSurface; self.senseID = senseID
        self.partOfSpeech = partOfSpeech; self.exampleEnglish = exampleEnglish; self.exampleMixed = exampleMixed
    }
    public func validated() throws -> Self {
        var copy = self
        copy.englishLemma = englishLemma.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        copy.targetLanguage = targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        copy.targetLemma = targetLemma.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        copy.targetSurface = targetSurface.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        copy.senseID = senseID.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.partOfSpeech = partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !copy.englishLemma.isEmpty, !copy.targetLemma.isEmpty, !copy.targetSurface.isEmpty,
              !copy.senseID.isEmpty, !copy.partOfSpeech.isEmpty,
              (2...3).contains(copy.targetLanguage.count),
              copy.targetLanguage.allSatisfy({ $0.isASCII && $0.isLetter }),
              [copy.englishLemma, copy.targetLemma, copy.targetSurface, copy.senseID].allSatisfy({ $0.count <= 500 })
        else { throw DomainError.invalidInput("Enter both expressions, a language code, and a distinct meaning.") }
        return copy
    }
}

public struct VocabularyItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let draft: VocabularyDraft
    public let createdAt: Date
    public init(id: String, draft: VocabularyDraft, createdAt: Date) {
        self.id = id; self.draft = draft; self.createdAt = createdAt
    }
}

public struct AppSettings: Codable, Sendable, Equatable {
    public var writingGenre: WritingGenre = .story
    public var replacementMode: ReplacementMode = .balanced
    public var practiceDomains: Set<PracticeDomain> = [.structure, .content, .actions]
    public var generationLevel: CEFRLevel = .c1
    public var defaultWordCount: Int = 110
    public var enabledLanguages: [String] = ["de", "ru"]
    public var languageWeights: [String: Double] = ["de": 0.5, "ru": 0.5]
    public var replacementDensity: ReplacementDensity = .medium
    /// Desired fraction of source words per language, before the shared 50% ceiling.
    /// An empty map migrates the earlier global density and relative shares without data loss.
    public var languageFrequencies: [String: Double] = [:]
    public var dailyReviewTarget: Int = 20
    public var desiredRetention: Double = 0.9
    public var preferredTopics: [String] = []
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case writingGenre, replacementMode, practiceDomains
        case generationLevel, defaultWordCount, enabledLanguages, languageWeights, replacementDensity,
             languageFrequencies, dailyReviewTarget, desiredRetention, preferredTopics
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        writingGenre = try c.decodeIfPresent(WritingGenre.self, forKey: .writingGenre) ?? .story
        replacementMode = try c.decodeIfPresent(ReplacementMode.self, forKey: .replacementMode) ?? .balanced
        practiceDomains = try c.decodeIfPresent(Set<PracticeDomain>.self, forKey: .practiceDomains) ?? [.structure, .content, .actions]
        generationLevel = try c.decodeIfPresent(CEFRLevel.self, forKey: .generationLevel) ?? .c1
        defaultWordCount = try c.decodeIfPresent(Int.self, forKey: .defaultWordCount) ?? 110
        enabledLanguages = try c.decodeIfPresent([String].self, forKey: .enabledLanguages) ?? ["de", "ru"]
        languageWeights = try c.decodeIfPresent([String: Double].self, forKey: .languageWeights) ?? ["de": 0.5, "ru": 0.5]
        replacementDensity = try c.decodeIfPresent(ReplacementDensity.self, forKey: .replacementDensity) ?? .medium
        languageFrequencies = try c.decodeIfPresent([String: Double].self, forKey: .languageFrequencies) ?? [:]
        dailyReviewTarget = try c.decodeIfPresent(Int.self, forKey: .dailyReviewTarget) ?? 20
        desiredRetention = try c.decodeIfPresent(Double.self, forKey: .desiredRetention) ?? 0.9
        preferredTopics = try c.decodeIfPresent([String].self, forKey: .preferredTopics) ?? []
    }
    public func frequency(for code: String) -> Double {
        if let explicit = languageFrequencies[code] { return explicit }
        let total = enabledLanguages.reduce(0.0) { $0 + (languageWeights[$1] ?? 0) }
        return total > 0 ? replacementDensity.target * (languageWeights[code] ?? 0) / total : 0
    }
    public var effectiveFrequencies: [String: Double] {
        let values = Dictionary(uniqueKeysWithValues: enabledLanguages.map { ($0, frequency(for: $0)) })
        let total = values.values.reduce(0, +)
        let scale = total > 0.5 ? 0.5 / total : 1
        return values.mapValues { $0 * scale }
    }
    /// Aggressive always attempts every eligible occurrence, independent of frequency settings.
    public var replacementLanguageShares: [String: Double] {
        if replacementMode == .aggressive {
            return Dictionary(uniqueKeysWithValues: enabledLanguages.map { ($0, 1.0 / Double(max(1, enabledLanguages.count))) })
        }
        return effectiveFrequencies.filter { $0.value > 0 }
    }
    public func validate() throws {
        guard (90...150).contains(defaultWordCount), (1...500).contains(dailyReviewTarget),
              desiredRetention.isFinite, (0.7...0.97).contains(desiredRetention),
              Set(enabledLanguages).count == enabledLanguages.count,
              enabledLanguages.allSatisfy({ (2...3).contains($0.count)
                  && $0.allSatisfy({ $0.isASCII && $0.isLetter && $0.isLowercase }) }),
              languageWeights.values.allSatisfy({ $0.isFinite && $0 >= 0 }),
              languageFrequencies.values.allSatisfy({ $0.isFinite && (0...0.5).contains($0) })
        else { throw DomainError.invalidInput("Check text length, language shares, and review limits.") }
    }
}

public struct UTF16Span: Codable, Sendable, Equatable {
    public let location: Int
    public let length: Int
    public init(location: Int, length: Int) { self.location = location; self.length = length }
    public func range(in text: String) throws -> Range<String.Index> {
        let total = text.utf16.count
        guard location >= 0, length > 0, location <= total, length <= total - location,
              let range = Range(NSRange(location: location, length: length), in: text),
              text.indices.contains(range.lowerBound),
              range.upperBound == text.endIndex || text.indices.contains(range.upperBound)
        else { throw DomainError.invalidSpan }
        return range
    }
}

public struct ReplacementSpan: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let sourceTextID: String
    public let originalUTF16Range: UTF16Span
    public let renderedUTF16Range: UTF16Span
    public let originalSurface: String
    public let originalLemma: String
    public let originalPartOfSpeech: String
    public let sourceSenseID: String
    public let senseDescription: String?
    public let targetLanguageCode: String
    public let targetLemma: String
    public let targetSurface: String
    public let translationConfidence: Double
    public let languagePackVersion: String
    public init(id: String = UUID().uuidString, sourceTextID: String, originalUTF16Range: UTF16Span,
                renderedUTF16Range: UTF16Span, originalSurface: String, originalLemma: String,
                originalPartOfSpeech: String, sourceSenseID: String, targetLanguageCode: String,
                targetLemma: String, targetSurface: String, translationConfidence: Double, languagePackVersion: String,
                senseDescription: String? = nil) {
        self.id = id; self.sourceTextID = sourceTextID; self.originalUTF16Range = originalUTF16Range
        self.renderedUTF16Range = renderedUTF16Range; self.originalSurface = originalSurface
        self.originalLemma = originalLemma; self.originalPartOfSpeech = originalPartOfSpeech
        self.senseDescription = senseDescription
        self.sourceSenseID = sourceSenseID; self.targetLanguageCode = targetLanguageCode
        self.targetLemma = targetLemma; self.targetSurface = targetSurface
        self.translationConfidence = translationConfidence; self.languagePackVersion = languagePackVersion
    }
}

public struct GeneratedText: Sendable, Equatable, Identifiable {
    public let id: String
    public let originalEnglish: String
    public let topic: String
    public let cefrLevel: CEFRLevel
    public let generatedAt: Date
    public let modelID: String
    public let seed: UInt32
    public let metadata: [String: String]
    public let replacements: [ReplacementSpan]
    public init(id: String = UUID().uuidString, originalEnglish: String, topic: String, cefrLevel: CEFRLevel,
                generatedAt: Date = .now, modelID: String, seed: UInt32,
                metadata: [String: String] = [:], replacements: [ReplacementSpan] = []) {
        self.id = id; self.originalEnglish = originalEnglish; self.topic = topic; self.cefrLevel = cefrLevel
        self.generatedAt = generatedAt; self.modelID = modelID; self.seed = seed
        self.metadata = metadata; self.replacements = replacements
    }
    public func renderedText() throws -> String {
        var output = "", cursor = originalEnglish.startIndex
        var previousEnd = 0
        guard Set(replacements.map(\.id)).count == replacements.count else { throw DomainError.invalidSpan }
        for span in replacements.sorted(by: { $0.originalUTF16Range.location < $1.originalUTF16Range.location }) {
            let range = try span.originalUTF16Range.range(in: originalEnglish)
            guard span.sourceTextID == id, span.originalUTF16Range.location >= previousEnd,
                  String(originalEnglish[range]) == span.originalSurface, !span.targetSurface.isEmpty,
                  span.translationConfidence.isFinite, (0...1).contains(span.translationConfidence)
            else { throw DomainError.invalidSpan }
            output += originalEnglish[cursor..<range.lowerBound]
            guard span.renderedUTF16Range.location == output.utf16.count,
                  span.renderedUTF16Range.length == span.targetSurface.utf16.count else { throw DomainError.invalidSpan }
            output += span.targetSurface; cursor = range.upperBound
            previousEnd = span.originalUTF16Range.location + span.originalUTF16Range.length
        }
        output += originalEnglish[cursor...]
        return output
    }
}

public struct StudySummary: Sendable, Equatable {
    public let newCards: Int
    public let dueCards: Int
    public let reviewedToday: Int
}
