import Foundation
import GRDB
import Testing
@testable import LinguaFrancaCore

private func latinFilterFixture() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
    let queue = try DatabaseQueue(path: url.path)
    try queue.write { db in
        try db.execute(sql: """
            CREATE TABLE family(id TEXT PRIMARY KEY,originLanguage TEXT,originWord TEXT,relationship TEXT,languages TEXT,searchKey TEXT);
            CREATE TABLE member(id TEXT PRIMARY KEY,familyID TEXT,language TEXT,sourceID TEXT,headword TEXT,english TEXT,pos TEXT,definition TEXT,path TEXT);
            CREATE INDEX member_family ON member(familyID,language,headword);
            """)
        func family(_ id: String, origin: String, entries: [(String, String, String)]) throws {
            try db.execute(sql: "INSERT INTO family VALUES(?,?,?,?,?,?)", arguments: [id, "lat", origin, "origin", "la,es,fr", OfflineDictionary.key(origin + " " + entries.map(\.1).joined(separator: " "))])
            for (index, entry) in entries.enumerated() {
                try db.execute(sql: "INSERT INTO member VALUES(?,?,?,?,?,?,?,?,?)", arguments: [id + String(index), id, entry.0, String(index), entry.1, "independent gloss", entry.2, "fixture definition", "[]"])
            }
        }
        try family("atlas", origin: "Atlas", entries: [
            ("la", "atlas", "noun"), ("es", "atlas", "noun"), ("fr", "atlas", "noun"),
            ("la", "Atlas", "proper_noun"), ("es", "Atlas", "proper_noun"), ("fr", "Atlas", "proper_noun"),
            ("es", "portar", "verb"), ("fr", "porter", "verb")])
        // Only the unfiltered family has two languages; no individual type does.
        try family("different-types", origin: "unshared", entries: [
            ("la", "bonus", "noun"), ("es", "bonifier", "verb"), ("fr", "Bon", "proper_noun")])
        // Nouns qualify for la-es, but not for es-fr.
        try family("carta", origin: "carta", entries: [
            ("la", "carta", "noun"), ("es", "carta", "noun"), ("fr", "cartographier", "verb")])
        // Selected native headwords, not historical origin labels, determine A-Z.
        try family("accent", origin: "z-root", entries: [("la", "ábel", "noun"), ("es", "abel", "noun")])
        try family("zebra", origin: "a-root", entries: [("es", "zebra", "noun"), ("fr", "zèbre", "noun")])
    }
    return url
}

@Test func latinWordTypesExcludeOtherSensesAndKeepTheNativePairValid() async throws {
    let url = try latinFilterFixture(); defer { try? FileManager.default.removeItem(at: url) }
    let latin = try LatinVocabulary(databaseURL: url)
    for type in [LatinVocabularyWordType.nouns, .verbs, .properNames] {
        let page = try await latin.search("", wordType: type)
        #expect(!page.families.contains { $0.id == "different-types" })
        for family in page.families {
            let members = try await latin.members(of: family.id, wordType: type)
            #expect(!members.isEmpty && members.allSatisfy { $0.record.partOfSpeech == type.rawValue })
            #expect(Set(members.map { $0.record.language }).count >= 2)
            #expect(Set(family.languages) == Set(members.map { $0.record.language }))
        }
    }
    #expect(try await latin.search("", pair: .latinSpanish, wordType: .nouns).families.contains { $0.id == "carta" })
    #expect(try await latin.search("", pair: .spanishFrench, wordType: .nouns).families.contains { $0.id == "carta" } == false)
    let verbs = try await latin.search("", pair: .spanishFrench, wordType: .verbs)
    #expect(verbs.families.map(\.id) == ["atlas"])
    #expect(verbs.families.first?.languages.contains("la") == false)
}

@Test func latinFilteredSearchAndCountsUseOnlyVisibleNativeSenses() async throws {
    let url = try latinFilterFixture(); defer { try? FileManager.default.removeItem(at: url) }
    let latin = try LatinVocabulary(databaseURL: url)
    #expect(try await latin.search("porter", wordType: .nouns).families.isEmpty)
    #expect(try await latin.search("porter", wordType: .verbs).families.map(\.id) == ["atlas"])
    #expect(try await latin.search("z-root", wordType: .nouns).families.isEmpty)
    #expect(try await latin.search("z-root").families.map(\.id) == ["accent"])
    #expect(try await latin.search("independent gloss").families.isEmpty)
    let names = try await latin.search("", wordType: .properNames)
    #expect(names.summary.families == 1 && names.summary.nativeWords == 3)
    #expect(names.families.map(\.displayWord) == ["Atlas"])
    let accent = try await latin.search("ABEL", wordType: .nouns)
    #expect(accent.families.map(\.id) == ["accent"])
    #expect(accent.summary.nativeWords == 2)
    #expect(try await latin.search("% ' OR 1=1 --", wordType: .verbs).families.isEmpty)
}

@Test func latinAlphabeticalPaginationUsesTheDisplayedWordAcrossAccentsAndCase() async throws {
    let url = try latinFilterFixture(); defer { try? FileManager.default.removeItem(at: url) }
    let latin = try LatinVocabulary(databaseURL: url)
    let all = try await latin.search("", wordType: .nouns, limit: 100)
    #expect(all.families.map(\.displayWord) == ["ábel", "atlas", "carta", "zebra"])
    #expect(try await latin.search("", limit: 100).families.map(\.originWord) == ["a-root", "Atlas", "carta", "unshared", "z-root"])
    let first = try await latin.search("", wordType: .nouns, limit: 2)
    let second = try await latin.search("", wordType: .nouns, offset: 2, limit: 2)
    #expect(first.hasMore && !second.hasMore)
    #expect(first.families.map(\.id) + second.families.map(\.id) == all.families.map(\.id))
    #expect(first.summary.families == 4 && first.summary.nativeWords == 9)
}
