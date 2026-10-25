import Foundation
import Testing
import GRDB
@testable import LinguaFrancaCore

@Test func fsrs6MatchesPinnedOfficialReferenceVectors() throws {
    struct Fixture:Decodable { let runs:[[Vector]] }
    struct Vector:Decodable { let delta:Double;let rating:Int;let stability:Double;let difficulty:Double;let state:String;let step:Int;let due:Double;let reviewedAt:Double }
    let url=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/fsrs6-reference.json")
    let fixture=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:url)),scheduler=try FSRS6()
    for run in fixture.runs {
        var card=SRSCard(vocabularyItemID:"word")
        for expected in run {
            card=try scheduler.review(card,rating:ReviewRating(rawValue:expected.rating)!,now:Date(timeIntervalSince1970:expected.reviewedAt))
            #expect(abs(card.stability-expected.stability) < 1e-9)
            #expect(abs(card.difficulty-expected.difficulty) < 1e-9)
            #expect(card.state.rawValue == expected.state)
            #expect(card.learningStep == expected.step)
            #expect(abs(card.dueAt.timeIntervalSince1970-expected.due) < 1e-5)
        }
    }
}

@Test func reviewsPersistAreAtomicAndCannotDoubleApply() async throws {
    let path=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".sqlite")
    defer { for suffix in ["","-wal","-shm"] { try? FileManager.default.removeItem(atPath:path.path+suffix) } }
    let db=try DatabaseManager(path:path.path),now=Date(timeIntervalSince1970:1_800_000_000)
    let deck=try await db.createDeck(name:"Words",now:now)
    let word=try await db.saveVocabulary(.init(englishLemma:"garden",targetLanguage:"de",targetLemma:"Garten",targetSurface:"Garten",senseID:"place"),inDeck:deck,now:now)
    let first=try #require(try await db.studyQueue(now:now).first?.card)
    let again=try await db.reviewCard(first,rating:.again,elapsedTime:2,now:now,eventID:"event")
    #expect(again.progress == .forgotten && again.dueAt == now.addingTimeInterval(60))
    #expect(try await db.reviewCard(first,rating:.again,elapsedTime:2,now:now,eventID:"event") == again)
    await #expect(throws:DomainError.self) { try await db.reviewCard(first,rating:.good,elapsedTime:2,now:now) }
    #expect(try await db.studyQueue(now:now).isEmpty)
    let reopened=try DatabaseManager(path:path.path)
    let pending=try #require(try await reopened.studyQueue(now:again.dueAt).first)
    #expect(pending.card == again && pending.word.id == word && pending.word.studyProgress == .forgotten)
    let good=try await reopened.reviewCard(again,rating:.good,elapsedTime:1,now:again.dueAt)
    #expect(good.progress == .studying)
    let learned=try await reopened.reviewCard(good,rating:.good,elapsedTime:1,now:good.dueAt)
    #expect(learned.progress == .learned && learned.state == .review)
    let forgotten=try await reopened.reviewCard(learned,rating:.again,elapsedTime:1,now:learned.dueAt)
    #expect(forgotten.progress == .forgotten && forgotten.lapses == 1)
    try await reopened.deleteDeck(id:deck)
    let queue=try DatabaseQueue(path:path.path)
    #expect(try await queue.read { try Int.fetchOne($0,sql:"SELECT count(*) FROM reviewLog") } == 4)
    #expect(try await reopened.vocabulary().first?.studyProgress == .forgotten)
    try await reopened.deleteVocabulary(id:word)
    #expect(try await queue.read { try Int.fetchOne($0,sql:"SELECT count(*) FROM reviewLog") } == 0)
}

@Test func dailyAdmissionLimitKeepsLearningDueAndSharedCardsUnique() async throws {
    let db=try DatabaseManager(),now=Date(timeIntervalSince1970:1_800_000_000)
    let a=try await db.createDeck(name:"A"),b=try await db.createDeck(name:"B")
    for i in 0..<3 {
        let draft=VocabularyDraft(englishLemma:"word\(i)",targetLanguage:"de",targetLemma:"Wort\(i)",targetSurface:"Wort\(i)",senseID:"sense")
        _=try await db.saveVocabulary(draft,inDeck:a,now:now)
        _=try await db.saveVocabulary(draft,inDeck:b,now:now)
    }
    let one=try await db.studyQueue(dailyTarget:1,now:now)
    #expect(one.count == 1)
    let learning=try await db.reviewCard(one[0].card,rating:.again,elapsedTime:1,now:now)
    #expect(try await db.studyQueue(dailyTarget:1,now:now).isEmpty)
    #expect(try await db.studyQueue(deckID:b,dailyTarget:1,now:learning.dueAt).map(\.id) == [learning.id])
    #expect(try await db.studyQueue(deckID:"missing",now:learning.dueAt).isEmpty)
    #expect(try await db.studyQueue(dailyTarget:1,now:now.addingTimeInterval(2*86400)).count == 2)
}

@Test func schedulerRejectsInvalidTimeAndRetention() throws {
    #expect(throws:DomainError.self) { try FSRS6(desiredRetention:.nan) }
    let scheduler=try FSRS6();let now=Date.now
    let card=try scheduler.review(.init(vocabularyItemID:"word"),rating:.good,now:now)
    #expect(throws:DomainError.self) { try scheduler.review(card,rating:.good,now:now.addingTimeInterval(-1)) }
    #expect(scheduler.retrievability(stability:card.stability,elapsedDays:0) == 1)
}
