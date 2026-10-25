import Foundation
import GRDB

/// Indexed read-only views over the same versioned language packs used by replacement.
public actor SemiticLexicon: SemiticMorphologyProviding {
    private let databases: [String:DatabaseQueue]
    public init(directory: URL) throws {
        var result: [String:DatabaseQueue] = [:]
        for language in SemiticLanguage.allCases {
            let manifest = directory.appendingPathComponent("en-"+language.rawValue+".json")
            guard FileManager.default.fileExists(atPath:manifest.path) else { continue }
            let metadata = try JSONDecoder().decode(LanguagePackMetadata.self,from:Data(contentsOf:manifest))
            guard metadata.schemaVersion == 1, metadata.languageCode == language.rawValue,
                  metadata.lexiconDatabaseName == URL(fileURLWithPath:metadata.lexiconDatabaseName).lastPathComponent else { throw DomainError.invalidInput("Invalid Semitic language pack.") }
            var configuration = Configuration(); configuration.readonly = true
            result[language.rawValue] = try DatabaseQueue(path:directory.appendingPathComponent(metadata.lexiconDatabaseName).path,configuration:configuration)
        }
        databases = result
    }
    public func availableLanguages() -> [String] { databases.keys.sorted() }
    public func roots(language: String? = nil, search: String = "", offset: Int = 0, limit: Int = 50) throws -> [SemiticRoot] {
        let offset = max(0,min(offset,20_000)), limit = max(1,min(limit,100)), query = SemiticUnicode.key(search.trimmingCharacters(in:.whitespacesAndNewlines))
        let compact = query.filter(\.isLetter)
        var result: [SemiticRoot] = []
        for code in databases.keys.sorted() where language == nil || code == language {
            result += try databases[code]!.read { db in
                try Row.fetchAll(db,sql:"""
                    SELECT r.*,(SELECT count(*) FROM semLexeme l WHERE l.rootID=r.id) AS lexemeCount
                    FROM semRoot r WHERE instr(r.searchKey,?)>0 OR replace(r.native,' ','')=?
                    ORDER BY r.native,r.id LIMIT ?
                    """,arguments:[query,compact,offset+limit]).map(Self.root)
            }
        }
        return Array(result.sorted { ($0.languageCode,$0.native,$0.id) < ($1.languageCode,$1.native,$1.id) }.dropFirst(offset).prefix(limit))
    }
    public func root(id: String, language: String) throws -> SemiticRoot? {
        try databases[language]?.read { db in
            try Row.fetchOne(db,sql:"SELECT r.*,(SELECT count(*) FROM semLexeme l WHERE l.rootID=r.id) AS lexemeCount FROM semRoot r WHERE r.id=?",arguments:[id]).map(Self.root)
        }
    }
    public func lexemes(rootID: String, language: String) throws -> [SemiticLexeme] {
        try databases[language]?.read { db in
            try Row.fetchAll(db,sql:"SELECT * FROM semLexeme WHERE rootID=? ORDER BY lemma,id LIMIT 200",arguments:[rootID]).map(Self.lexeme)
        } ?? []
    }
    public func lexeme(id: String, language: String) throws -> SemiticLexeme? {
        try databases[language]?.read { db in try Row.fetchOne(db,sql:"SELECT * FROM semLexeme WHERE id=?",arguments:[id]).map(Self.lexeme) }
    }
    public func verifiedForms(for reference: SemiticVocabularyReference) throws -> [SemiticWordForm] {
        try reference.validate()
        let column: String, id: String
        switch reference.kind { case .root: column="rootID"; id=reference.rootID!; case .lexeme: column="lexemeID"; id=reference.lexemeID!; case .wordForm: column="id"; id=reference.wordFormID! }
        return try databases[reference.languageCode]?.read { db in
            try Row.fetchAll(db,sql:"SELECT * FROM semForm WHERE \(column)=? AND status='attested' ORDER BY CASE WHEN tags LIKE '%canonical%' THEN 0 ELSE 1 END,id LIMIT 512",arguments:[id]).map(Self.form)
        } ?? []
    }
    public func examples(rootID: String, language: String, limit: Int = 12) throws -> [SemiticExample] {
        try databases[language]?.read { db in
            let limit=max(1,min(limit,100))
            let dictionary=try Row.fetchAll(db,sql:"SELECT e.* FROM semExample e JOIN semLexeme l ON l.id=e.lexemeID WHERE l.rootID=? ORDER BY e.id LIMIT ?",arguments:[rootID,limit]).map(Self.example)
            let corpus=try Row.fetchAll(db,sql:"SELECT DISTINCT t.*,s.lexemeID FROM semCorpusTemplate t JOIN semCorpusSlot s ON s.templateID=t.id JOIN semLexeme l ON l.id=s.lexemeID WHERE l.rootID=? ORDER BY t.id LIMIT ?",arguments:[rootID,limit]).map { r in
                SemiticExample(id:r["id"],lexemeID:r["lexemeID"],text:r["text"],translation:"",transliteration:"",reference:r["reference"],source:r["source"])
            }
            return Array((corpus+dictionary).prefix(limit))
        } ?? []
    }
    public func forms(matching surface: String, language: String) throws -> [SemiticWordForm] {
        try databases[language]?.read { db in
            try Row.fetchAll(db,sql:"SELECT * FROM semForm WHERE normalized=? AND status='attested' ORDER BY id LIMIT 128",arguments:[SemiticUnicode.key(surface)]).map(Self.form)
        } ?? []
    }
    public func examples(forLexemeIDs ids: [String], language: String) throws -> [SemiticExample] {
        guard !ids.isEmpty, ids.count <= 512 else { return [] }
        return try databases[language]?.read { db in
            try Row.fetchAll(db,sql:"SELECT * FROM semExample WHERE lexemeID IN (\(Array(repeating:"?",count:ids.count).joined(separator:","))) ORDER BY id LIMIT 200",arguments:StatementArguments(ids)).map(Self.example)
        } ?? []
    }
    public func relationships(rootID: String, language: String) throws -> [SemiticRelationship] {
        let families: [String] = try databases[language]?.read { try String.fetchAll($0,sql:"SELECT familyID FROM semRelationship WHERE rootID=?",arguments:[rootID]) } ?? []
        var result: [SemiticRelationship] = []
        for code in databases.keys.sorted() {
            for family in families {
                result += try databases[code]!.read { db in
                    try Row.fetchAll(db,sql:"""
                        SELECT r.*,(SELECT count(*) FROM semLexeme l WHERE l.rootID=r.id) AS lexemeCount,
                        f.label AS family,x.evidence AS evidence,x.source AS relationshipSource
                        FROM semRelationship x JOIN semRoot r ON r.id=x.rootID JOIN semFamily f ON f.id=x.familyID
                        WHERE x.familyID=? AND r.id<>? ORDER BY r.id
                        """,arguments:[family,rootID]).map { .init(root:Self.root($0),family:$0["family"],evidence:$0["evidence"],source:$0["relationshipSource"]) }
                }
            }
        }
        return result
    }
    public func corpusTemplates(lexemeIDs: [String]) throws -> [SyriacCorpusTemplate] {
        guard !lexemeIDs.isEmpty,lexemeIDs.count<=512,let database=databases["syc"] else { return [] }
        return try database.read { db in
            let placeholders=Array(repeating:"?",count:lexemeIDs.count).joined(separator:",")
            let templates=try Row.fetchAll(db,sql:"SELECT DISTINCT t.* FROM semCorpusTemplate t JOIN semCorpusSlot s ON s.templateID=t.id WHERE s.lexemeID IN (\(placeholders)) ORDER BY t.id LIMIT 160",arguments:StatementArguments(lexemeIDs))
            return try templates.map { row in
                let id: String=row["id"]
                let slots=try Row.fetchAll(db,sql:"SELECT f.*,s.start AS start,s.length AS length FROM semCorpusSlot s JOIN semForm f ON f.id=s.formID WHERE s.templateID=? ORDER BY s.start",arguments:[id]).map { slot in
                    SyriacCorpusSlot(range:.init(location:slot["start"],length:slot["length"]),form:try Self.form(slot))
                }
                return .init(id:id,text:row["text"],reference:row["reference"],source:row["source"],groupID:row["groupID"],slots:slots)
            }
        }
    }
    private static func root(_ r: Row) -> SemiticRoot {
        .init(id:r["id"],languageCode:r["language"],native:r["native"],transliteration:r["transliteration"],meaning:r["meaning"],source:r["source"],etymology:r["etymology"],lexemeCount:r["lexemeCount"])
    }
    private static func lexeme(_ r: Row) -> SemiticLexeme {
        .init(id:r["id"],languageCode:r["language"],lemma:r["lemma"],transliteration:r["transliteration"],gloss:r["gloss"],partOfSpeech:r["pos"],pattern:r["pattern"],source:r["source"],etymology:r["etymology"],rootID:r["rootID"])
    }
    private static func form(_ r: Row) throws -> SemiticWordForm {
        .init(id:r["id"],lexemeID:r["lexemeID"],surface:r["surface"],transliteration:r["transliteration"],source:r["source"],rootID:r["rootID"],tags:try JSONDecoder().decode([String].self,from:Data((r["tags"] as String).utf8)),status:MorphologicalAttestation(rawValue:r["status"]) ?? .unsupported)
    }
    private static func example(_ r: Row) -> SemiticExample {
        .init(id:r["id"],lexemeID:r["lexemeID"],text:r["text"],translation:r["translation"],transliteration:r["transliteration"],reference:r["reference"],source:r["source"])
    }
}
