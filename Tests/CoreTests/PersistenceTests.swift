import Foundation
import Testing
import GRDB
@testable import LinguaFrancaCore

private func word(_ sense: String = "financial") -> VocabularyDraft {
    VocabularyDraft(englishLemma: "bank", targetLanguage: "de", targetLemma: "Bank", targetSurface: "Bank", senseID: sense, partOfSpeech: "noun")
}

@Test func persistenceSurvivesReopeningAndMigration() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
    defer { for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
    let first = try DatabaseManager(path: url.path)
    let deck = try await first.createDeck(name: "German")
    let id = try await first.saveVocabulary(word(), inDeck: deck)
    var settings = AppSettings(); settings.defaultWordCount = 130
    try await first.saveSettings(settings)
    let second = try DatabaseManager(path: url.path)
    #expect(try await second.decks().first?.id == deck)
    #expect(try await second.vocabulary().first?.id == id)
    #expect(try await second.settings() == settings)
    let queue = try DatabaseQueue(path: url.path)
    let migrations = try await queue.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations") }
    #expect(migrations == ["v1_local_foundation"])
    #expect(try await queue.read { try Row.fetchAll($0, sql: "PRAGMA foreign_key_check").isEmpty })
}

@Test func duplicateMembershipsAndDistinctSenses() async throws {
    let db = try DatabaseManager()
    let a = try await db.createDeck(name: "One"), b = try await db.createDeck(name: "Two")
    let id = try await db.saveVocabulary(word(), inDeck: a)
    #expect(try await db.saveVocabulary(word(), inDeck: a) == id)
    #expect(try await db.saveVocabulary(word(), inDeck: b) == id)
    _ = try await db.saveVocabulary(word("river"), inDeck: a)
    #expect(try await db.vocabulary().count == 2)
    #expect(try await db.decks().map(\.wordCount).sorted() == [1, 2])
    #expect(try await db.studySummary().newCards == 2)
    try await db.deleteDeck(id: a)
    #expect(try await db.vocabulary().count == 2)
    #expect(try await db.vocabulary(deckID: b).count == 1)
    try await db.deleteVocabulary(id: id)
    #expect(try await db.studySummary().newCards == 1)
    #expect(try await db.storageBytes() > 0)
}

@Test func reopenAndListChangesPreserveExistingReviewHistory() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
    defer { for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
    let db = try DatabaseManager(path: url.path), deck = try await db.createDeck(name: "History")
    _ = try await db.saveVocabulary(word(), inDeck: deck)
    let queue = try DatabaseQueue(path: url.path)
    try await queue.write { connection in
        let card = try String.fetchOne(connection, sql: "SELECT id FROM srsCard")!
        try connection.execute(sql: "INSERT INTO reviewLog VALUES (?, ?, 3, ?, 12, 1, 'fixture-prior', 'fixture-result', 'fixture-only')",
                               arguments: [UUID().uuidString, card, Date.now.timeIntervalSince1970])
    }
    let reopened = try DatabaseManager(path: url.path)
    try await reopened.renameDeck(id: deck, name: "Renamed")
    try await reopened.deleteDeck(id: deck)
    #expect(try await queue.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM reviewLog") } == 1)
    #expect(try await reopened.studySummary().reviewedToday == 1)
}

@Test func invalidDeckAndWordRollBack() async throws {
    let db = try DatabaseManager()
    await #expect(throws: DomainError.self) { try await db.createDeck(name: "  ") }
    let deck = try await db.createDeck(name: "My list")
    await #expect(throws: DomainError.self) { try await db.createDeck(name: "my LIST") }
    await #expect(throws: DomainError.self) { try await db.saveVocabulary(word(), inDeck: "missing") }
    #expect(try await db.vocabulary().isEmpty)
    var invalid = word(); invalid.senseID = ""
    await #expect(throws: DomainError.self) { try await db.saveVocabulary(invalid, inDeck: deck) }
    #expect(try await db.studySummary().newCards == 0)
}

@Test func vocabularyEditingUnicodeAndLiteralSearch() async throws {
    let db = try DatabaseManager(), draft = VocabularyDraft(englishLemma: "decision", targetLanguage: "ru", targetLemma: "решение", targetSurface: "решение", senseID: "choice")
    let deck = try await db.createDeck(name: "Русский")
    let id = try await db.saveVocabulary(draft, inDeck: deck)
    #expect(try await db.vocabulary(search: "РЕШЕНИЕ").count == 1)
    #expect(try await db.vocabulary(search: "%' OR 1=1 --").isEmpty)
    var edited = draft; edited.exampleEnglish = "A deliberate choice."
    try await db.updateVocabulary(id: id, draft: edited)
    #expect(try await db.vocabulary(search: "deliberate").first?.id == id)
    try await db.removeVocabulary(id: id, fromDeck: deck)
    #expect(try await db.vocabulary(deckID: deck).isEmpty)
    #expect(try await db.vocabulary().count == 1)
}

@Test func settingsValidateBeforeOverwriting() async throws {
    let db = try DatabaseManager()
    let settings = AppSettings(); try await db.saveSettings(settings)
    var invalid = settings; invalid.languageFrequencies = ["de": -0.1]
    await #expect(throws: DomainError.self) { try await db.saveSettings(invalid) }
    #expect(try await db.settings() == settings)
    invalid = settings; invalid.defaultWordCount = 1000
    await #expect(throws: DomainError.self) { try await db.saveSettings(invalid) }
    var empty = settings; empty.enabledLanguages = []
    try await db.saveSettings(empty)
    #expect(try await db.settings().enabledLanguages.isEmpty)
}

@Test func concurrentSavesRemainUnique() async throws {
    let db = try DatabaseManager(), deck = try await db.createDeck(name: "Concurrent")
    try await withThrowingTaskGroup(of: String.self) { group in
        for _ in 0..<20 { group.addTask { try await db.saveVocabulary(word(), inDeck: deck) } }
        for try await _ in group {}
    }
    #expect(try await db.vocabulary().count == 1)
    #expect(try await db.studySummary().newCards == 1)
}

@Test func removingFormerSamplesPreservesRealReadingsAndUserLibrary() async throws {
    let db = try DatabaseManager()
    let deck = try await db.createDeck(name: "My own list")
    let wordID = try await db.saveVocabulary(word(), inDeck: deck)
    var settings = AppSettings(); settings.dailyReviewTarget = 15
    try await db.saveSettings(settings)
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let real = GeneratedText(id: "real", originalEnglish: "A genuine model reading.", topic: "Science", cefrLevel: .c1,
        generatedAt: date, modelID: "Qwen3.5-0.8B-Q4_K_M", seed: 42, metadata: ["contentSource": "local-model"])
    try await db.savePassage(real)
    try await db.savePassage(GeneratedText(originalEnglish: "Old fixture.", topic: "Test", cefrLevel: .b2, modelID: "sample-preview", seed: 0))
    try await db.savePassage(GeneratedText(originalEnglish: "Tagged fixture.", topic: "Test", cefrLevel: .b2, modelID: "legacy", seed: 0,
        metadata: ["contentSource": "hand-authored-sample"]))
    #expect(try await db.removeSamplePassages() == 2)
    #expect(try await db.removeSamplePassages() == 0)
    #expect(try await db.recentPassages() == [real])
    #expect(try await db.vocabulary().first?.id == wordID)
    #expect(try await db.decks().first?.id == deck)
    #expect(try await db.studySummary().newCards == 1)
    #expect(try await db.settings() == settings)
}
