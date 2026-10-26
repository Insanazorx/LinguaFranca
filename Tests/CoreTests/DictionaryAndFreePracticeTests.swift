import Foundation
import Testing
@testable import LinguaFrancaCore

private var dictionaryDirectory:URL {URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/LanguagePacks")}

@Test func allDownloadedDictionariesAreSearchableInBothDirections() async throws {
    let dictionary=try OfflineDictionary(directory:dictionaryDirectory),packs=try await dictionary.packs()
    #expect(Set(packs.map(\.id)) == ["de","ru","ar","he","syc","la","es","fr"])
    #expect(packs.allSatisfy {$0.entries>1000})
    #expect(packs.filter { ["de","ru","ar","he","syc"].contains($0.id) }.allSatisfy {$0.forms>1000})
    #expect(packs.first {$0.id=="ar"}!.forms>1_000_000)
    let banks=try await dictionary.search("bank",language:"de",limit:100)
    #expect(banks.records.filter {$0.english=="bank" && $0.kind == .entry}.count>1)
    let german=try await dictionary.search("Häuser",language:"de",limit:100)
    var hasHouse=false
    for record in german.records where record.kind == .entry {
        if try await dictionary.detail(record).translations.contains(where: {$0.lowercased()=="haus"}) {hasHouse=true;break}
    }
    #expect(hasHouse)
    let hebrew=try await dictionary.search("כָּתַבְתִּי",language:"he")
    #expect(hebrew.records.contains {$0.kind == .lexeme})
    let syriac=try await dictionary.search("ܟܬܒ",language:"syc")
    #expect(!syriac.records.isEmpty)
}

@Test func dictionaryPaginationFormsAndLiteralQueriesPreserveDistinctRecords() async throws {
    let dictionary=try OfflineDictionary(directory:dictionaryDirectory)
    let first=try await dictionary.search("",language:"de",limit:7),second=try await dictionary.search("",language:"de",offset:7,limit:7)
    #expect(first.hasMore && first.records.count==7 && second.records.count==7)
    #expect(Set(first.records.map(\.id)).isDisjoint(with:second.records.map(\.id)))
    #expect(try await dictionary.search("needlezzx' OR 1=1 --").records.isEmpty)
    #expect(try await dictionary.search("%[]:").records.isEmpty)
    let matches=try await dictionary.search("house",language:"de",limit:100)
    var detail:DictionaryDetail?
    for record in matches.records where record.english=="house" && record.kind == .entry {
        let candidate=try await dictionary.detail(record)
        if candidate.translations.contains("Haus") {detail=candidate;break}
    }
    let house=try #require(detail)
    let forms=try await dictionary.forms(house,target:"Haus",limit:3),next=try await dictionary.forms(house,target:"Haus",offset:3,limit:3)
    #expect(forms.hasMore && forms.forms.count==3)
    #expect(Set(forms.forms.map(\.id)).isDisjoint(with:next.forms.map(\.id)))
    #expect(try house.vocabularyDraft(target:"Haus").validated().senseID == house.senseID)
    #expect(try await dictionary.meaning(for:house.vocabularyDraft(target:"Haus")) == house.record.definition)
}

@Test func voluntaryPracticeIncludesFutureCardsAndUpdatesForgottenListImmediately() async throws {
    let db=try DatabaseManager(),now=Date.now,deck=try await db.createDeck(name:"Free practice")
    for word in ["garden","moon"] {
        _=try await db.saveVocabulary(.init(englishLemma:word,targetLanguage:"de",targetLemma:word,targetSurface:word,senseID:"fixture"),inDeck:deck,now:now)
    }
    let initial=try await db.practiceCards(deckID:deck)
    #expect(initial.count==2 && initial.allSatisfy {$0.card.vocabularyItemID==$0.word.id && $0.card.id != $0.word.id})
    _=try await db.reviewCard(initial[0].card,rating:.easy,elapsedTime:1,now:now)
    _=try await db.reviewCard(initial[1].card,rating:.again,elapsedTime:1,now:now)
    #expect(try await db.studyQueue(dailyTarget:1,now:now).isEmpty)
    let available=try await db.practiceCards(deckID:deck)
    #expect(available.count==2 && available.allSatisfy {$0.card.dueAt>now})
    let forgotten=try await db.practiceCards(deckID:deck,forgottenOnly:true)
    #expect(forgotten.count==1)
    _=try await db.reviewCard(forgotten[0].card,rating:.good,elapsedTime:1,now:now.addingTimeInterval(1))
    #expect(try await db.practiceCards(deckID:deck,forgottenOnly:true).isEmpty)
    #expect(try await db.practiceCards(deckID:deck).count==2)
    #expect(try await db.practiceCards(deckID:"missing").isEmpty)
}

@Test func freePracticeHasNoFiveHundredCardOrDailyCap() async throws {
    let db=try DatabaseManager(),deck=try await db.createDeck(name:"Large list")
    for i in 0..<505 {_=try await db.saveVocabulary(.init(englishLemma:"word\(i)",targetLanguage:"de",targetLemma:"target\(i)",targetSurface:"target\(i)",senseID:"fixture"),inDeck:deck)}
    #expect(try await db.practiceCards(deckID:deck).count==505)
}

@Test func cardDragRequiresAnIntentionalHorizontalRelease() {
    #expect(CardDragDecision.rating(x:120,y:60,cardWidth:320) == .good)
    #expect(CardDragDecision.rating(x:-120,y:60,cardWidth:320) == .again)
    #expect(CardDragDecision.rating(x:20,y:300,cardWidth:320) == nil)
    #expect(CardDragDecision.rating(x:100,y:300,cardWidth:320) == nil)
    #expect(CardDragDecision.rating(x:30,y:10,cardWidth:320) == nil)
    #expect(CardDragDecision.rating(x:100,y:0,cardWidth:900) == nil)
    #expect(CardDragDecision.rating(x:.nan,y:0,cardWidth:320) == nil)
}
