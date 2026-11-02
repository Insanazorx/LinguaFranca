import Foundation
import GRDB
import Testing
@testable import LinguaFrancaCore

private func question(_ id:String="one",source:CatalogPracticeSource = .latin) -> CatalogQuestion {
    .init(id:source.rawValue+":"+id,familyID:"family-"+id,familyTitle:"Book",language:source == .latin ? "la" : "ar",word:source == .latin ? "liber" : "كِتَاب",meaning:"book",partOfSpeech:"noun",sourceID:id,source:source,context:CatalogContexts.make(english:"book",pos:"noun"))
}
@Test func catalogScoresResetCombosAndContextIsSenseBound() throws {
    var score=CatalogScore(sessionID:"round")
    score.record(recalled:true,context:false);#expect(score.points==10 && score.combo==1)
    score.record(recalled:true,context:true);#expect(score.points==25 && score.combo==2)
    score.record(recalled:true,context:false);#expect(score.points==45 && score.combo==3)
    score.record(recalled:false,context:true);#expect(score.points==45 && score.combo==0 && score.bestCombo==3)
    #expect(CatalogContexts.make(english:"bank",pos:"noun")==nil)
    #expect(CatalogContexts.make(english:"book",pos:"verb")==nil)
    #expect(CatalogContexts.semitic(meaning:"dog; insulting sense",pos:"noun")?.english=="dog")
    #expect(CatalogContexts.semitic(meaning:"dog keeper",pos:"noun")==nil)
    #expect(CatalogContexts.make(english:"book",pos:"noun")?.original=="I opened the book and read the next chapter.")
}
@Test func catalogReviewsUseRealFSRSAndAreAtomicIdempotentAndPersistent() async throws {
    let path=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".sqlite")
    defer {for suffix in ["","-wal","-shm"] {try? FileManager.default.removeItem(atPath:path.path+suffix)}}
    let db=try DatabaseManager(path:path.path),now=Date(timeIntervalSince1970:2_000_000)
    let q=question(),start=try await db.startCatalogPractice([q],source:.latin,now:now)
    let initial=try #require(start.cards.first)
    let result=try await db.reviewCatalogCard(initial.card,question:q,sessionID:start.score.sessionID,rating:.good,usedContext:true,now:now,eventID:"first")
    #expect(result.card == (try FSRS6().review(initial.card,rating:.good,now:now)))
    #expect(result.score.points==15 && result.score.combo==1)
    let duplicate=try await db.reviewCatalogCard(initial.card,question:q,sessionID:start.score.sessionID,rating:.good,usedContext:true,now:now,eventID:"first")
    #expect(duplicate.score==result.score && duplicate.card==result.card)
    await #expect(throws:DomainError.self) {try await db.reviewCatalogCard(initial.card,question:q,sessionID:start.score.sessionID,rating:.good,usedContext:false,now:now,eventID:"stale")}
    let reopened=try DatabaseManager(path:path.path)
    let next=try await reopened.startCatalogPractice([q],source:.latin,now:now)
    #expect(next.cards.first?.card==result.card)
    let stats=try await reopened.catalogStats(source:.latin)
    #expect(stats.answers==1 && stats.points==15 && stats.bestCombo==1)
    let empty=try await reopened.catalogStats(source:.semitic)
    #expect(empty.answers==0 && empty.points==0)
    #expect(try await reopened.dueCatalogQuestions(source:.latin,now:now).isEmpty)
    #expect(try await reopened.dueCatalogQuestions(source:.latin,now:now.addingTimeInterval(601)).map(\.id)==[q.id])
    try await reopened.endCatalogPractice(sessionID:start.score.sessionID,now:now)
    await #expect(throws:DomainError.self) {try await reopened.reviewCatalogCard(result.card,question:q,sessionID:start.score.sessionID,rating:.again,usedContext:false,now:now)}
    #expect(try await reopened.vocabulary().isEmpty)
    let queue=try DatabaseQueue(path:path.path)
    #expect(try await queue.read{try Int.fetchOne($0,sql:"SELECT count(*) FROM catalogReview")}==1)
    #expect(try await queue.read{try Row.fetchAll($0,sql:"PRAGMA foreign_key_check").isEmpty})
}
@Test func catalogSessionCannotReviewAnOutsideCardAndQueueNeverFinishes() async throws {
    let db=try DatabaseManager(),now=Date(timeIntervalSince1970:2_000_000)
    let q=question(),outside=question("outside")
    let a=try await db.startCatalogPractice([q],source:.latin,now:now)
    let b=try await db.startCatalogPractice([outside],source:.latin,now:now)
    await #expect(throws:DomainError.self) {try await db.reviewCatalogCard(b.cards[0].card,question:outside,sessionID:a.score.sessionID,rating:.good,usedContext:false,now:now)}
    var queue=CatalogPracticeQueue(cards:a.cards,now:now)
    let fsrs=try FSRS6()
    for step in 0..<30 {
        let card=try #require(queue.current)
        try queue.record(fsrs.review(card.card,rating:step%4==0 ? .again : .good,now:now.addingTimeInterval(Double(step))),now:now.addingTimeInterval(Double(step)))
    }
    #expect(queue.current != nil && queue.reviews==30 && queue.count==1)
    var rng=SeededGenerator(seed:42)
    let sampled=CatalogSampling.families(["a","b","c","d"],preferred:["outside","b"],limit:3,rng:&rng)
    #expect(sampled.count==3 && sampled.contains("b") && !sampled.contains("outside"))
}
@Test func bundledSemiticComparisonsSearchASCIIAndUseWordsInsteadOfBareRoots() async throws {
    let packs=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/LanguagePacks")
    let lexicon=try SemiticLexicon(directory:packs),families=try #require(lexicon.families)
    let a=try await families.search("k l b",pair:.triple)
    #expect(a.families.contains{$0.label=="k-l-b"})
    #expect(try await families.search("K-L-B",pair:.triple).families.map(\.id)==a.families.map(\.id))
    #expect(try await lexicon.roots(language:"ar",search:"k  l  b").contains{$0.native=="ك ل ب"})
    #expect(try await families.search("' b d").families.contains{$0.label=="ʿ-b-d"})
    for pair in SemiticFamilyPair.allCases {
        let page=try await families.search(pair:pair,limit:100)
        #expect(page.total>0)
        for f in page.families {#expect(Set(pair.languages).isSubset(of:Set(f.languages)) && f.languages.count>=2)}
    }
    let questions=try await families.practiceQuestions(lexicon:lexicon,query:"k l b",pair:.triple,families:1,seed:42)
    #expect(Set(questions.map(\.language))==["ar","he","syc"])
    #expect(questions.allSatisfy{!$0.word.contains("-") && !$0.word.contains(" ") && !$0.sourceID.isEmpty})
    for q in questions {
        let l=try #require(try await lexicon.lexeme(id:q.sourceID,language:q.language))
        #expect(q.word==l.lemma && q.meaning==l.gloss && l.rootID != nil)
        #expect(!(try await lexicon.verifiedForms(for:l.reference)).isEmpty)
    }
    let same=try await families.practiceQuestions(lexicon:lexicon,query:"k l b",pair:.triple,families:1,seed:42)
    #expect(same==questions)
    let shuffled=try await families.practiceQuestions(lexicon:lexicon,families:8,seed:42)
    #expect(shuffled.contains{$0.context != nil})
}

@Test func latinPracticeRespectsPairWordTypeAndSeed() async throws {
    let packs=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/LanguagePacks")
    let catalog=try LatinVocabulary(databaseURL:packs.appendingPathComponent("_latin/etymology.sqlite"))
    let questions=try await catalog.practiceQuestions(pair:.spanishFrench,wordType:.verbs,families:8,seed:123)
    #expect(!questions.isEmpty && questions.count<=16)
    #expect(Set(questions.map(\.language))==["es","fr"])
    #expect(questions.allSatisfy{$0.partOfSpeech=="verb" && $0.context==nil})
    #expect(Set(questions.map(\.id)).count==questions.count)
    #expect(try await catalog.practiceQuestions(pair:.spanishFrench,wordType:.verbs,families:8,seed:123)==questions)
    for q in questions {
        let members=try await catalog.members(of:q.familyID,wordType:.verbs)
        #expect(members.contains{$0.record.sourceID==q.sourceID && $0.record.headword==q.word})
    }
    let triples=try await catalog.search("",pair:.triple,limit:10)
    #expect(!triples.families.isEmpty && triples.families.allSatisfy{Set($0.languages)==["la","es","fr"]})
    let nouns=try await catalog.practiceQuestions(wordType:.nouns,families:8,seed:123)
    #expect(nouns.contains{$0.context != nil})
}
