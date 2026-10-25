import Foundation
import Testing
@testable import LinguaFrancaCore

private let studyNow = Date(timeIntervalSince1970: 1_800_000_000)
private func fixture(_ id: String, state: CardState = .new, due: Double = 0) -> StudyCard {
    let word = VocabularyItem(id: id, draft: .init(englishLemma: id, targetLanguage: "de", targetLemma: id, targetSurface: id, senseID: "fixture"), createdAt: studyNow)
    var card = SRSCard(id: "card-" + id, vocabularyItemID: id, dueAt: studyNow.addingTimeInterval(due))
    card.state = state
    if state != .new { card.repetitions = 1; card.stability = 2; card.difficulty = 5; card.lastReviewedAt = studyNow.addingTimeInterval(-86400) }
    return StudyCard(card: card, word: word)
}

@Test func continuousStudyPrioritizesDueLearningThenDueReviews() throws {
    let learning = fixture("learning", state: .learning, due: -2)
    let review = fixture("review", state: .review, due: -100)
    var session = ContinuousStudySession(cards: [fixture("new"), review, learning], now: studyNow)
    #expect(session.current?.id == learning.id)
    let updated = try FSRS6().review(learning.card, rating: .good, now: studyNow)
    try session.record(updated, now: studyNow)
    #expect(session.current?.id == review.id)
}

@Test func continuousStudyNeverFinishesAndUsesFreshSnapshots() throws {
    let scheduler = try FSRS6()
    var session = ContinuousStudySession(cards: (0..<5).map {fixture("word-\($0)")}, now: studyNow)
    var counts: [String: Int] = [:]
    var previous: String?
    for turn in 0..<200 {
        let current = try #require(session.current)
        #expect(current.id != previous)
        counts[current.id, default: 0] += 1
        let now = studyNow.addingTimeInterval(Double(turn))
        let updated = try scheduler.review(current.card, rating: .good, now: now)
        try session.record(updated, now: now)
        previous = current.id
    }
    #expect(session.reviewCount == 200 && session.current != nil)
    #expect(counts.count == 5 && counts.values.max()! - counts.values.min()! <= 1)
}

@Test func oneCardRepeatsAndEmptySelectionsStayEmpty() throws {
    let one = fixture("only")
    var session = ContinuousStudySession(cards: [one, one], now: studyNow)
    #expect(session.count == 1)
    for i in 0..<8 {
        let current = try #require(session.current)
        let now = studyNow.addingTimeInterval(Double(i))
        try session.record(FSRS6().review(current.card, rating: .again, now: now), now: now)
        #expect(session.current?.card.repetitions == i + 1)
        #expect(session.current?.word.studyProgress == .forgotten)
    }
    #expect(ContinuousStudySession(cards: []).current == nil)
}

@Test func continuousStudyRejectsStaleUpdatesAndReconcilesOnlySelectedWords() throws {
    let a = fixture("a"), b = fixture("b"), outside = fixture("outside")
    var session = ContinuousStudySession(cards: [a, b], now: studyNow)
    #expect(throws: DomainError.self) { try session.record(a.card, now: studyNow) }
    #expect(session.reviewCount == 0)
    session.reconcile([b, outside], now: studyNow)
    #expect(session.count == 1 && session.current?.id == b.id)
    session.reconcile([outside], now: studyNow)
    #expect(session.count == 0 && session.current == nil)
}

@Test func continuousStudyPersistsEveryReappearanceWithoutStaleCardErrors() async throws {
    let db = try DatabaseManager(), deck = try await db.createDeck(name: "Endless")
    for name in ["garden", "moon"] {
        _ = try await db.saveVocabulary(.init(englishLemma: name, targetLanguage: "de", targetLemma: name, targetSurface: name, senseID: "fixture"), inDeck: deck, now: studyNow)
    }
    var session = ContinuousStudySession(cards: try await db.practiceCards(deckID: deck), now: studyNow)
    for i in 0..<20 {
        let card = try #require(session.current?.card), now = studyNow.addingTimeInterval(Double(i))
        let updated = try await db.reviewCard(card, rating: i.isMultiple(of: 3) ? .again : .good, elapsedTime: 1, now: now)
        try session.record(updated, now: now)
    }
    let saved = try await db.practiceCards(deckID: deck)
    #expect(saved.reduce(0) { $0 + $1.card.repetitions } == 20)
    #expect(saved.allSatisfy { $0.card.schedulerVersion == FSRS6.version })
    #expect(session.current != nil)
}

@Test func reviewReturnsTheExactStoredSnapshotAtFractionalTimestamps() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 814_000_000.0000001)
    let db = try DatabaseManager(), deck = try await db.createDeck(name: "Precision")
    _ = try await db.saveVocabulary(.init(englishLemma: "moon", targetLanguage: "de", targetLemma: "Mond", targetSurface: "Mond", senseID: "fixture"), inDeck: deck, now: now)
    let original = try #require(try await db.practiceCards(deckID: deck).first?.card)
    let saved = try await db.reviewCard(original, rating: .again, elapsedTime: 0.1, now: now, eventID: "fractional")
    #expect(saved == (try await db.practiceCards(deckID: deck).first?.card))
    #expect(try await db.reviewCard(original, rating: .again, elapsedTime: 0.1, now: now, eventID: "fractional") == saved)
    let next = try await db.reviewCard(saved, rating: .good, elapsedTime: 0.1, now: now.addingTimeInterval(0.23456789))
    #expect(next.repetitions == 2)
    #expect(next == (try await db.practiceCards(deckID: deck).first?.card))
}
