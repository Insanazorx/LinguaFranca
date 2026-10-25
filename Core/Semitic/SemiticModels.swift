import Foundation

public enum SemiticLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case arabic = "ar", hebrew = "he", syriac = "syc"
    public var id: String { rawValue }
    public var title: String {
        switch self { case .arabic: "Modern Standard Arabic"; case .hebrew: "Modern Hebrew"; case .syriac: "Classical Syriac" }
    }
}

public enum MorphologicalAttestation: String, Codable, Sendable { case attested, generated, unsupported }
public enum SemiticSelectionKind: String, Codable, Sendable { case root, lexeme, wordForm }

public struct SemiticVocabularyReference: Codable, Sendable, Equatable {
    public let languageCode: String
    public let kind: SemiticSelectionKind
    public let rootID: String?
    public let lexemeID: String?
    public let wordFormID: String?
    public init(languageCode: String, kind: SemiticSelectionKind, rootID: String?, lexemeID: String? = nil, wordFormID: String? = nil) {
        self.languageCode = languageCode; self.kind = kind; self.rootID = rootID; self.lexemeID = lexemeID; self.wordFormID = wordFormID
    }
    public func validate() throws {
        guard SemiticLanguage(rawValue:languageCode) != nil,
              (kind != .root || rootID != nil), (kind != .lexeme || lexemeID != nil), (kind != .wordForm || wordFormID != nil),
              [rootID,lexemeID,wordFormID].compactMap({$0}).allSatisfy({ !$0.isEmpty && $0.count <= 100 })
        else { throw DomainError.invalidInput("The saved lexical reference is incomplete.") }
    }
}

public struct SemiticRoot: Identifiable, Sendable, Equatable {
    public let id, languageCode, native, transliteration, meaning, source, etymology: String
    public let lexemeCount: Int
    public var reference: SemiticVocabularyReference { .init(languageCode:languageCode,kind:.root,rootID:id) }
    public var vocabularyDraft: VocabularyDraft {
        .init(englishLemma:String(meaning.prefix(400)),targetLanguage:languageCode,targetLemma:native,targetSurface:native,
              senseID:"root:"+id,partOfSpeech:"root",lexicalReference:reference)
    }
}

public struct SemiticLexeme: Identifiable, Sendable, Equatable {
    public let id, languageCode, lemma, transliteration, gloss, partOfSpeech, pattern, source, etymology: String
    public let rootID: String?
    public var reference: SemiticVocabularyReference { .init(languageCode:languageCode,kind:.lexeme,rootID:rootID,lexemeID:id) }
    public var vocabularyDraft: VocabularyDraft {
        .init(englishLemma:String(gloss.prefix(400)),targetLanguage:languageCode,targetLemma:lemma,targetSurface:lemma,
              senseID:id,partOfSpeech:partOfSpeech,lexicalReference:reference)
    }
}

public struct SemiticWordForm: Identifiable, Sendable, Equatable, Codable {
    public let id, lexemeID, surface, transliteration, source: String
    public let rootID: String?
    public let tags: [String]
    public let status: MorphologicalAttestation
    public var analysis: String { tags.joined(separator:" · ") }
    public func vocabularyDraft(for lexeme: SemiticLexeme) -> VocabularyDraft {
        .init(englishLemma:String(lexeme.gloss.prefix(400)),targetLanguage:lexeme.languageCode,targetLemma:lexeme.lemma,targetSurface:surface,
              senseID:"form:"+id,partOfSpeech:lexeme.partOfSpeech,lexicalReference:.init(languageCode:lexeme.languageCode,kind:.wordForm,rootID:rootID,lexemeID:lexemeID,wordFormID:id))
    }
}

public struct SemiticExample: Identifiable, Sendable, Equatable {
    public let id, lexemeID, text, translation, transliteration, reference, source: String
}

public struct SemiticRelationship: Identifiable, Sendable {
    public var id: String { root.id + family }
    public let root: SemiticRoot
    public let family, evidence, source: String
}

public enum SemiticUnicode {
    /// Search/matching only. Stored strings and all displayed UTF-16 offsets stay original.
    public static func key(_ value: String) -> String {
        String(value.decomposedStringWithCanonicalMapping.unicodeScalars.filter { !CharacterSet.nonBaseCharacters.contains($0) })
            .precomposedStringWithCanonicalMapping.lowercased()
    }
    public static func isRightToLeft(_ language: String) -> Bool { SemiticLanguage(rawValue:language) != nil }
    public static func scriptMatches(_ value: String, language: String) -> Bool {
        let bounds: ClosedRange<UInt32>
        switch language { case "ar": bounds = 0x600...0x6FF; case "he": bounds = 0x590...0x5FF; case "syc": bounds = 0x700...0x74F; default: return false }
        let letters = value.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        return !letters.isEmpty && Double(letters.filter { bounds.contains($0.value) }.count)/Double(letters.count) >= 0.95
    }
}

public protocol SemiticMorphologyProviding: Sendable {
    func verifiedForms(for reference: SemiticVocabularyReference) async throws -> [SemiticWordForm]
}
