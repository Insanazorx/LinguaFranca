import Foundation
import GRDB

public struct LatinVocabularyFamily: Identifiable, Sendable {
    public let id,latin,english,partOfSpeech:String
}
public struct LatinVocabularyMember: Identifiable, Sendable {
    public let id:String
    public let record:DictionaryRecord
    /// Source word first, then each recorded historical ancestor up to Latin.
    public let originPath:[String]
}
public struct LatinVocabularyPage:Sendable {
    public let families:[LatinVocabularyFamily]
    public let hasMore:Bool
}
public actor LatinVocabulary {
    private let database:DatabaseQueue
    public init(databaseURL:URL) throws {
        var config=Configuration();config.readonly=true
        database=try DatabaseQueue(path:databaseURL.path,configuration:config)
    }
    public func search(_ text:String,offset:Int=0,limit:Int=40) throws -> LatinVocabularyPage {
        guard text.count<=200,offset>=0 else {throw DomainError.invalidInput("Use a shorter search.")}
        try Task.checkCancellation()
        let query=OfflineDictionary.key(text.trimmingCharacters(in:.whitespacesAndNewlines)),size=max(1,min(limit,100))
        let rows=try database.read { db in
            try Row.fetchAll(db,sql:"SELECT * FROM family WHERE instr(searchKey,?)>0 ORDER BY english,latin,id LIMIT ? OFFSET ?",arguments:[query,size+1,offset]).map {
                LatinVocabularyFamily(id:$0["id"],latin:$0["latin"],english:$0["english"],partOfSpeech:$0["pos"])
            }
        }
        return .init(families:Array(rows.prefix(size)),hasMore:rows.count>size)
    }
    public func members(of familyID:String) throws -> [LatinVocabularyMember] {
        try database.read { db in
            try Row.fetchAll(db,sql:"SELECT * FROM member WHERE familyID=? ORDER BY CASE language WHEN 'la' THEN 0 WHEN 'es' THEN 1 ELSE 2 END,headword,id",arguments:[familyID]).map { row in
                .init(id:row["id"],record:.init(language:row["language"],kind:.entry,sourceID:row["sourceID"],headword:row["headword"],english:row["english"],partOfSpeech:row["pos"],definition:row["definition"],transliteration:""),originPath:try JSONDecoder().decode([String].self,from:Data((row["path"] as String).utf8)))
            }
        }
    }
}
