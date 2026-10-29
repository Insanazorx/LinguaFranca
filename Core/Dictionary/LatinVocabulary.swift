import Foundation
import GRDB

public enum LatinVocabularyPair: String, CaseIterable, Identifiable, Sendable {
    case all, latinSpanish, latinFrench, spanishFrench
    public var id: Self { self }
    public var title: String {
        switch self {
        case .all: "All pairs"
        case .latinSpanish: "Latin · Spanish"
        case .latinFrench: "Latin · French"
        case .spanishFrench: "Spanish · French"
        }
    }
    public var languages: [String] {
        switch self {
        case .all: []
        case .latinSpanish: ["la", "es"]
        case .latinFrench: ["la", "fr"]
        case .spanishFrench: ["es", "fr"]
        }
    }
}
public enum LatinVocabularyWordType: String, CaseIterable, Identifiable, Sendable {
    case all, nouns = "noun", verbs = "verb", properNames = "proper_noun"
    public var id: Self { self }
    public var title: String {
        switch self {
        case .all: "All words"
        case .nouns: "Nouns"
        case .verbs: "Verbs"
        case .properNames: "Proper names"
        }
    }
}
public struct LatinVocabularyFamily: Identifiable, Sendable {
    public let id, originLanguage, originWord, displayWord: String
    public let relationship: String
    /// Only languages with entries of the selected word type.
    public let languages: [String]
    public var hasRecordedOrigin: Bool { relationship == "origin" }
}
public struct LatinVocabularyMember: Identifiable, Sendable {
    public let id: String
    public let record: DictionaryRecord
    /// Native headword followed by its recorded historical ancestors; never English.
    public let originPath: [String]
}
public struct LatinVocabularyPage: Sendable {
    public let families: [LatinVocabularyFamily]
    public let hasMore: Bool
    public let summary: LatinVocabularySummary
}
public struct LatinVocabularySummary: Sendable {
    public let families, nativeWords: Int
}
public actor LatinVocabulary {
    private let database: DatabaseQueue
    public init(databaseURL: URL) throws {
        var config = Configuration(); config.readonly = true
        config.prepareDatabase { db in
            db.add(collation: DatabaseCollation("latinAlphabetical") { lhs, rhs in
                OfflineDictionary.key(lhs).compare(OfflineDictionary.key(rhs), options: [.numeric], locale: Locale(identifier: "en_US_POSIX"))
            })
            db.add(function: DatabaseFunction("latinWordKey", argumentCount: 1, pure: true) { values in
                String.fromDatabaseValue(values[0]).map(OfflineDictionary.key)
            })
        }
        database = try DatabaseQueue(path: databaseURL.path, configuration: config)
    }
    public func summary() throws -> LatinVocabularySummary {
        try database.read { db in
            .init(families: try Int.fetchOne(db, sql: "SELECT count(*) FROM family") ?? 0,
                  nativeWords: try Int.fetchOne(db, sql: "SELECT count(*) FROM (SELECT DISTINCT language,headword FROM member)") ?? 0)
        }
    }
    public func search(_ text: String, pair: LatinVocabularyPair = .all, wordType: LatinVocabularyWordType = .all,
                       offset: Int = 0, limit: Int = 40) throws -> LatinVocabularyPage {
        guard text.count <= 200, offset >= 0 else { throw DomainError.invalidInput("Use a shorter search.") }
        try Task.checkCancellation()
        let query = OfflineDictionary.key(text.trimmingCharacters(in: .whitespacesAndNewlines)), size = max(1, min(limit, 100))
        let prefix = Self.filteredFamilies(query: query, pair: pair, wordType: wordType)
        return try database.read { db in
            let rows = try Row.fetchAll(db, sql: prefix.sql + " SELECT * FROM filtered ORDER BY displayWord COLLATE latinAlphabetical,displayWord,id LIMIT ? OFFSET ?", arguments: prefix.arguments + [size + 1, offset])
            let families = rows.prefix(size).map {
                LatinVocabularyFamily(id: $0["id"], originLanguage: $0["originLanguage"], originWord: $0["originWord"], displayWord: $0["displayWord"], relationship: $0["relationship"], languages: ($0["languages"] as String).split(separator: ",").map(String.init))
            }
            let counts = try Row.fetchOne(db, sql: prefix.sql + """
                SELECT (SELECT count(*) FROM filtered) AS families,
                    (SELECT count(*) FROM (SELECT DISTINCT m.language,m.headword FROM chosen m JOIN filtered f ON f.id=m.familyID)) AS words
                """, arguments: prefix.arguments)!
            return .init(families: families, hasMore: rows.count > size, summary: .init(families: counts["families"], nativeWords: counts["words"]))
        }
    }
    /// Filter native senses before grouping. A family must still contain two
    /// qualifying languages; the requested pair must qualify in this same type.
    private static func filteredFamilies(query: String, pair: LatinVocabularyPair, wordType: LatinVocabularyWordType) -> (sql: String, arguments: StatementArguments) {
        var args: StatementArguments = []
        let predicate: String
        if wordType == .all { predicate = "1" }
        else { predicate = "pos=?"; args += [wordType.rawValue] }
        var having = "count(DISTINCT language)>=2"
        for code in pair.languages {
            having += " AND sum(CASE WHEN language=? THEN 1 ELSE 0 END)>0"; args += [code]
        }
        let display = wordType == .all ? "f.originWord" : "g.preferredWord"
        var sql = """
            WITH chosen AS (SELECT familyID,language,headword FROM member WHERE \(predicate)),
            qualifying AS (
                SELECT familyID,group_concat(DISTINCT language) AS languages,
                    coalesce(min(CASE WHEN language='la' THEN headword END COLLATE latinAlphabetical),
                             min(CASE WHEN language='es' THEN headword END COLLATE latinAlphabetical),
                             min(CASE WHEN language='fr' THEN headword END COLLATE latinAlphabetical)) AS preferredWord
                FROM chosen GROUP BY familyID HAVING \(having)
            ), filtered AS (
                SELECT f.id,f.originLanguage,f.originWord,f.relationship,g.languages,\(display) AS displayWord
                FROM family f JOIN qualifying g ON g.familyID=f.id
            """
        if !query.isEmpty {
            // Hidden noun/proper-name/verb senses must not produce search hits.
            sql += " WHERE (EXISTS(SELECT 1 FROM chosen m WHERE m.familyID=f.id AND instr(latinWordKey(m.headword),?)>0)"
            args += [query]
            if wordType == .all { sql += " OR instr(latinWordKey(f.originWord),?)>0"; args += [query] }
            sql += ")"
        }
        return (sql + ")", args)
    }
    public func members(of familyID: String, wordType: LatinVocabularyWordType = .all) throws -> [LatinVocabularyMember] {
        try Task.checkCancellation()
        return try database.read { db in
            var sql = "SELECT * FROM member WHERE familyID=?"
            var args: StatementArguments = [familyID]
            if wordType != .all { sql += " AND pos=?"; args += [wordType.rawValue] }
            sql += " ORDER BY CASE language WHEN 'la' THEN 0 WHEN 'es' THEN 1 ELSE 2 END,headword COLLATE latinAlphabetical,headword,pos,id"
            return try Row.fetchAll(db, sql: sql, arguments: args).map { row in
                .init(id: row["id"], record: .init(language: row["language"], kind: .entry, sourceID: row["sourceID"], headword: row["headword"], english: row["english"], partOfSpeech: row["pos"], definition: row["definition"], transliteration: ""), originPath: try JSONDecoder().decode([String].self, from: Data((row["path"] as String).utf8)))
            }
        }
    }
}
