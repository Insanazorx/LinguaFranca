import Foundation
import GRDB

public enum StudyListDestination: Sendable { case existing(String), new(String) }
public struct PassageVocabularyImport: Sendable {
    public let deckID:String
    public let added:Int
    public let alreadyPresent:Int
}

public extension GeneratedText {
    /// Retain each distinct target expression and meaning, with its original sentence.
    /// English words without a translation are not turned into misleading study cards.
    func studyVocabulary() throws -> [VocabularyDraft] {
        _ = try renderedText()
        var drafts:[VocabularyDraft]=[],seen:Set<String>=[]
        for span in replacements.sorted(by: { $0.originalUTF16Range.location<$1.originalUTF16Range.location }) {
            let context=try vocabularyContext(for:span)
            let draft=try VocabularyDraft(englishLemma:span.originalLemma,targetLanguage:span.targetLanguageCode,
                targetLemma:span.targetLemma,targetSurface:span.targetSurface,senseID:span.sourceSenseID,
                partOfSpeech:span.originalPartOfSpeech,exampleEnglish:context.english,exampleMixed:context.mixed,
                lexicalReference:span.lexicalReference).validated()
            let key=String(decoding:try JSONEncoder().encode([draft.englishLemma.lowercased(),draft.targetLanguage,draft.targetLemma,draft.senseID,draft.partOfSpeech]),as:UTF8.self)
            if seen.insert(key).inserted { drafts.append(draft) }
        }
        return drafts
    }
}

public extension DatabaseManager {
    /// List creation, memberships and new cards commit together. Existing cards and review
    /// histories are reused; importing a passage twice never resets their schedule.
    func addPassageVocabulary(_ passage:GeneratedText,to destination:StudyListDestination,now:Date = .now) async throws -> PassageVocabularyImport {
        let drafts=try passage.studyVocabulary()
        guard !drafts.isEmpty else { throw DomainError.invalidInput("This text has no translated expressions to add.") }
        return try await queue.write { db in
            let deckID:String
            switch destination {
            case .existing(let id):
                guard try String.fetchOne(db,sql:"SELECT id FROM studyDeck WHERE id=?",arguments:[id]) != nil else { throw DomainError.missingRecord }
                deckID=id
            case .new(let name):
                let clean=try Self.deckName(name);deckID=UUID().uuidString
                guard try String.fetchOne(db,sql:"SELECT id FROM studyDeck WHERE nameKey=?",arguments:[Self.key(clean)]) == nil else { throw DomainError.invalidInput("A list with this name already exists.") }
                try db.execute(sql:"INSERT INTO studyDeck VALUES(?,?,?,?,?)",arguments:[deckID,clean,Self.key(clean),now.timeIntervalSince1970,now.timeIntervalSince1970])
            }
            let before=try Int.fetchOne(db,sql:"SELECT count(*) FROM deckVocabulary WHERE deckID=?",arguments:[deckID]) ?? 0
            for draft in drafts { _ = try Self.saveVocabulary(draft,inDeck:deckID,now:now,db:db) }
            let after=try Int.fetchOne(db,sql:"SELECT count(*) FROM deckVocabulary WHERE deckID=?",arguments:[deckID]) ?? 0
            return .init(deckID:deckID,added:after-before,alreadyPresent:drafts.count-(after-before))
        }
    }
}
