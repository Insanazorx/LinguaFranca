import Foundation
import GRDB

public enum SemiticFamilyPair: String, CaseIterable, Identifiable, Sendable {
    case all, arabicHebrew, arabicSyriac, hebrewSyriac, triple
    public var id: Self { self }
    public var title: String {
        switch self {
        case .all: "All pairs & triples"
        case .arabicHebrew: "Arabic · Hebrew"
        case .arabicSyriac: "Arabic · Syriac"
        case .hebrewSyriac: "Hebrew · Syriac"
        case .triple: "All three languages"
        }
    }
    public var languages: [String] {
        switch self {
        case .all: []
        case .arabicHebrew: ["ar","he"]
        case .arabicSyriac: ["ar","syc"]
        case .hebrewSyriac: ["he","syc"]
        case .triple: ["ar","he","syc"]
        }
    }
}
public struct SemiticFamilyNote: Decodable, Sendable {
    public var summary = ""
    public var contrast = ""
    public var usage: [String:String] = [:]
    public var related: [String] = []
    public var sources: [String] = []
    enum CodingKeys: String, CodingKey { case summary, contrast, usage, related, sources }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        contrast = try c.decodeIfPresent(String.self, forKey: .contrast) ?? ""
        usage = try c.decodeIfPresent([String:String].self, forKey: .usage) ?? [:]
        related = try c.decodeIfPresent([String].self, forKey: .related) ?? []
        sources = try c.decodeIfPresent([String].self, forKey: .sources) ?? []
    }
}
public struct SemiticFamily: Identifiable, Sendable {
    public let id, label, basis: String
    public let languages: [String]
    public let note: SemiticFamilyNote
    public var evidenceTitle: String {
        basis == "reviewed" ? "Reviewed comparison" : basis == "historical" ? "Recorded historical link" : "Matching consonants"
    }
}
public struct SemiticFamilyPage: Sendable {
    public let families: [SemiticFamily]
    public let total: Int
    public let hasMore: Bool
}
public enum SemiticRootSearch {
    /// Lossy aliases are for finding entries only, never for proving relationships.
    public static func key(_ value: String) -> String {
        let folded = SemiticUnicode.key(value).replacingOccurrences(of:"ʕ",with:"'")
            .replacingOccurrences(of:"ʿ",with:"'").replacingOccurrences(of:"ʾ",with:"'").replacingOccurrences(of:"ʔ",with:"'")
        return folded.filter { $0.isLetter || $0.isNumber || $0 == "'" }
    }
}
public actor SemiticFamilies {
    let database: DatabaseQueue
    public init(databaseURL: URL) throws {
        var c = Configuration(); c.readonly = true
        database = try DatabaseQueue(path: databaseURL.path, configuration: c)
    }
    static func predicate(_ text: String, pair: SemiticFamilyPair) throws -> (String, StatementArguments) {
        guard text.count <= 200 else { throw DomainError.invalidInput("Use a shorter root search.") }
        var sql = "1", args: StatementArguments = []
        for language in pair.languages {
            sql += " AND EXISTS(SELECT 1 FROM member m WHERE m.familyID=f.id AND m.language=?)"; args += [language]
        }
        let query = text.trimmingCharacters(in:.whitespacesAndNewlines)
        if !query.isEmpty {
            sql += " AND (instr(f.searchKey,?)>0 OR instr(f.searchKey,?)>0)"
            let compact=SemiticRootSearch.key(query)
            args += [query.lowercased(), compact.isEmpty ? query.lowercased() : compact]
        }
        return (sql,args)
    }
    public func search(_ text: String = "", pair: SemiticFamilyPair = .all, offset: Int = 0, limit: Int = 40) throws -> SemiticFamilyPage {
        guard offset >= 0 else { throw DomainError.invalidInput("Invalid root page.") }
        let (sql,args) = try Self.predicate(text,pair:pair), size = max(1,min(100,limit))
        return try database.read { db in
            let rows = try Row.fetchAll(db,sql:"SELECT f.* FROM family f WHERE \(sql) ORDER BY f.label,f.id LIMIT ? OFFSET ?",arguments:args + [size+1,offset])
            return .init(families:try rows.prefix(size).map(Self.family),total:try Int.fetchOne(db,sql:"SELECT count(*) FROM family f WHERE \(sql)",arguments:args) ?? 0,hasMore:rows.count>size)
        }
    }
    public func members(of id: String) throws -> [SemiticRoot] {
        try database.read { db in
            try Row.fetchAll(db,sql:"SELECT * FROM member WHERE familyID=? ORDER BY language,native,rootID",arguments:[id]).map { r in
                .init(id:r["rootID"],languageCode:r["language"],native:r["native"],transliteration:r["transliteration"],meaning:r["meaning"],source:r["source"],etymology:r["etymology"],lexemeCount:r["lexemeCount"])
            }
        }
    }
    static func family(_ r: Row) throws -> SemiticFamily {
        .init(id:r["id"],label:r["label"],basis:r["basis"],languages:(r["languages"] as String).split(separator:",").map(String.init),note:try JSONDecoder().decode(SemiticFamilyNote.self,from:Data((r["note"] as String).utf8)))
    }
}
