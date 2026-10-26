import Foundation
import CryptoKit
import GRDB
import Testing
@testable import LinguaFrancaCore

private var addonPacks:URL { URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/LanguagePacks") }

@Test func studyCardInspectionUsesItsSavedSenseAndDoesNotInventAnExactMatch() async throws {
    let dictionary=try OfflineDictionary(directory:addonPacks)
    let house=try await dictionary.search("house",language:"fr",limit:100)
    let record=try #require(house.records.first { $0.english=="house" && $0.partOfSpeech=="noun" })
    let detail=try await dictionary.detail(record),draft=detail.vocabularyDraft(target:record.headword)
    let linked=try await dictionary.inspect(draft)
    #expect(linked.exact?.sourceID==record.sourceID && linked.exact?.language=="fr")
    let modelWord=VocabularyDraft(englishLemma:"house",targetLanguage:"fr",targetLemma:record.headword,targetSurface:record.headword,senseID:"local-model:unknown",partOfSpeech:"noun")
    let unlinked=try await dictionary.inspect(modelWord)
    #expect(unlinked.exact==nil && !unlinked.candidates.isEmpty)
    #expect(unlinked.candidates.allSatisfy { $0.language=="fr" && $0.english=="house" })
    let unknown=VocabularyDraft(englishLemma:"missing",targetLanguage:"zz",targetLemma:"missing",targetSurface:"missing",senseID:"unknown")
    #expect(try await dictionary.inspect(unknown).candidates.isEmpty)
}

@Test func englishLookupShowsEveryLanguageAndPreservesHomonyms() async throws {
    let dictionary=try OfflineDictionary(directory:addonPacks)
    let groups=try await dictionary.englishTranslations(" HOUSE ",limitPerLanguage:100)
    #expect(Set(groups.map(\.id)) == ["de","ru","ar","he","syc","la","es","fr"])
    #expect(groups.allSatisfy { !$0.records.isEmpty && $0.records.allSatisfy { $0.english=="house" } })
    let banks=try await dictionary.englishTranslations("bank",limitPerLanguage:100)
    #expect(banks.first { $0.id=="fr" }!.records.count>1)
    let missing=try await dictionary.englishTranslations("' OR 1=1 --")
    #expect(missing.count==8 && missing.allSatisfy { $0.records.isEmpty })
    for group in groups where ["la","es","fr"].contains(group.id) {
        let detail=try await dictionary.detail(group.records[0])
        #expect(!detail.translations.isEmpty)
        _ = try await dictionary.forms(detail,target:detail.translations[0])
    }
}

@Test func importedFormsAreSearchableAndAvailableForWritingPractice() async throws {
    let dictionary=try OfflineDictionary(directory:addonPacks)
    let spanish=try await dictionary.search("casas",language:"es",limit:100)
    #expect(spanish.records.contains { $0.english=="house" })
    let french=try SQLiteLanguagePack(manifestURL:addonPacks.appendingPathComponent("en-fr.json"))
    #expect(try await french.practiceSurfaces(targetLemma:"parler",partOfSpeech:"verb").contains("parlons"))
    let latin=try SQLiteLanguagePack(manifestURL:addonPacks.appendingPathComponent("en-la.json"))
    #expect(try await latin.practiceSurfaces(targetLemma:"aqua",partOfSpeech:"noun").contains { OfflineDictionary.key($0)=="aquam" })
}

@Test func newLanguageScriptsSupportAccentsAndRejectWrongScripts() throws {
    for (code,word) in [("la","līber"),("es","mañana"),("fr","cœur"),("fr","école") ] {
        let slot=AggressiveSlot(source:"word",range:.init(location:0,length:4),language:code,partOfSpeech:"noun")
        #expect(AggressiveCoverageValidator.validTarget(word,slot:slot))
        #expect(!AggressiveCoverageValidator.validTarget("слово",slot:slot))
        let request=VocabularyPracticeRequest(languageCode:code,expressions:[.init(id:"word",target:word,english:"word",meaning:"test")])
        try request.validate()
        #expect(request.prompt.contains(request.languageName))
        #expect(!request.systemInstruction.contains("русском"))
        var settings=AppSettings();settings.replacementMode = .aggressive;settings.enabledLanguages=[code];settings.practiceDomains=[.content]
        let task=try AggressiveModelTask(settings:settings,repair:.init(english:"word",slots:[slot]))
        #expect(task.grammar.contains(#"\u00C0-\u024F"#))
    }
    let latin=VocabularyPracticeRequest(languageCode:"la",expressions:[.init(id:"1",target:"librum",english:"book",meaning:"test")])
    #expect(try VocabularyPracticeValidator.validate("Marcus librum legit. Puella in horto ambulat.",request:latin).contains("librum"))
    #expect(throws:GenerationError.self) {try VocabularyPracticeValidator.validate("Marcus librum legit. The child reads a book in the garden every morning.",request:latin)}
}

@Test func newPacksParticipateInBalancedAndAggressiveWithoutChangingDefaults() async throws {
    let registry=try LanguagePackRegistry(directory:addonPacks)
    #expect(AppSettings().enabledLanguages == ["de","ru"])
    for code in ["la","es","fr"] {
        let pack=try #require(registry.packs.first { $0.metadata.languageCode==code })
        #expect(try await pack.lookup(englishLemma:"house").count>0)
        var settings=AppSettings();settings.enabledLanguages=[code];settings.languageFrequencies=[code:0.5]
        let engine=ContextualReplacementEngine(registry:registry)
        let text="The house has a garden. A dog waits beside the door. The moon shines above the village. A book lies on the table."
        let balanced=try await engine.replace(text:text,sourceTextID:code,settings:settings,seed:42)
        #expect(!balanced.spans.isEmpty)
        #expect(balanced.spans.allSatisfy { $0.targetLanguageCode==code })
        settings.replacementMode = .aggressive;settings.practiceDomains=[.structure]
        let task=try AggressiveModelTask(settings:settings)
        let slots=try await AggressiveCoverageValidator(registry:registry).preparedSlots(english:"Tea and coffee before lunch.",task:task)
        #expect(!slots.isEmpty && slots.allSatisfy { $0.language==code && $0.writingProfile != nil })
    }
}

private func bulkPassage() -> GeneratedText {
    let source="🌍 A book rests beside a book. A river bank is peaceful. The bank holds money."
    var cursor=source.startIndex,delta=0,spans:[ReplacementSpan]=[]
    for (original,target,code,sense) in [("book","livre","fr","reading"),("book","livre","fr","reading"),("bank","rīpa","la","river"),("bank","banco","es","finance")] {
        let range=source.range(of:original,range:cursor..<source.endIndex)!,ns=NSRange(range,in:source)
        spans.append(.init(sourceTextID:"bulk",originalUTF16Range:.init(location:ns.location,length:ns.length),renderedUTF16Range:.init(location:ns.location+delta,length:target.utf16.count),originalSurface:original,originalLemma:original,originalPartOfSpeech:"noun",sourceSenseID:sense,targetLanguageCode:code,targetLemma:target,targetSurface:target,translationConfidence:0.9,languagePackVersion:"fixture"))
        delta+=target.utf16.count-ns.length;cursor=range.upperBound
    }
    return .init(id:"bulk",originalEnglish:source,topic:"Reading",cefrLevel:.c1,modelID:"fixture",seed:1,replacements:spans)
}

@Test func bulkImportIsAtomicIdempotentAndPreservesReviewHistory() async throws {
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer {try? FileManager.default.removeItem(at:folder)}
    let db=try DatabaseManager(path:folder.appendingPathComponent("library.sqlite").path),passage=bulkPassage()
    let drafts=try passage.studyVocabulary()
    #expect(drafts.count==3)
    #expect(drafts[0].exampleEnglish=="🌍 A book rests beside a book.")
    #expect(drafts[0].exampleMixed.contains("livre"))
    let first=try await db.addPassageVocabulary(passage,to:.new("From a text"))
    #expect(first.added==3 && first.alreadyPresent==0)
    let cards=try await db.practiceCards(deckID:first.deckID)
    let reviewed=try await db.reviewCard(cards[0].card,rating:.easy,elapsedTime:2)
    let second=try await db.addPassageVocabulary(passage,to:.existing(first.deckID))
    #expect(second.added==0 && second.alreadyPresent==3)
    let after=try await db.practiceCards(deckID:first.deckID)
    #expect(after.first { $0.card.id==reviewed.id }!.card==reviewed)
    let copy=try await db.addPassageVocabulary(passage,to:.new("Another list"))
    #expect(copy.added==3)
    #expect(try await db.vocabulary().count==3)
    #expect(try await db.practiceCards().count==3)
    await #expect(throws:DomainError.self) {try await db.addPassageVocabulary(passage,to:.new("Another list"))}
    #expect(try await db.decks().count==2)
    let reopened=try DatabaseManager(path:folder.appendingPathComponent("library.sqlite").path)
    #expect(try await reopened.practiceCards().first { $0.card.id==reviewed.id }!.card==reviewed)
    let empty=GeneratedText(originalEnglish:"Nothing is translated.",topic:"Empty",cefrLevel:.b2,modelID:"fixture",seed:1)
    await #expect(throws:DomainError.self) {try await db.addPassageVocabulary(empty,to:.new("Must not exist"))}
    #expect(try await db.decks().count==2)
}

private func fixtureAddon(at folder:URL,code:String="pt") throws {
    try FileManager.default.createDirectory(at:folder.appendingPathComponent("_dictionary"),withIntermediateDirectories:true)
    let metadata=LanguagePackMetadata(id:"en-"+code,languageCode:code,displayName:"Portuguese fixture",version:"fixture-1",schemaVersion:1,lexiconDatabaseName:"en-"+code+".sqlite",supportedFeatures:["indexed-lookup"],licenseMetadata:["license":"test-only"],writingProfile:.init(script:.latin,generationName:"Portuguese"))
    let data=try JSONEncoder().encode(metadata)
    try data.write(to:folder.appendingPathComponent(metadata.id+".json"))
    try Data("Test-only fixture, no production translations.".utf8).write(to:folder.appendingPathComponent("LICENSE.txt"))
    let lexicon=try DatabaseQueue(path:folder.appendingPathComponent(metadata.lexiconDatabaseName).path)
    try lexicon.write { db in
        try db.execute(sql:"CREATE TABLE entry(lemma TEXT,pos TEXT,senseID TEXT,definition TEXT,translations TEXT,score REAL,provenance TEXT)")
        try db.execute(sql:"INSERT INTO entry VALUES('house','noun','fixture','a building','[\"casa\"]',1,'{\"source\":\"fixture\"}')")
    }
    let index=try DatabaseQueue(path:folder.appendingPathComponent("_dictionary/search.sqlite").path)
    try index.write { db in
        try db.execute(sql:"""
            CREATE TABLE document(id INTEGER PRIMARY KEY,language TEXT,kind TEXT,sourceID TEXT,headword TEXT,english TEXT,pos TEXT,definition TEXT,transliteration TEXT,englishKey TEXT,searchText TEXT);
            CREATE TABLE pack(language TEXT,metadata TEXT,entryCount INTEGER,lexemeCount INTEGER,rootCount INTEGER,formCount INTEGER);
            CREATE TABLE target(documentID INTEGER,key TEXT);
            CREATE TABLE nativeForm(language TEXT,key TEXT,lemmaKey TEXT);
            CREATE VIRTUAL TABLE search USING fts5(searchText,content='document',content_rowid='id');
            """)
        try db.execute(sql:"INSERT INTO pack VALUES(?,?,1,0,0,0)",arguments:[code,String(decoding:data,as:UTF8.self)])
        try db.execute(sql:"INSERT INTO document VALUES(1,?,'entry','1','casa','house','noun','a building','','house','house casa')",arguments:[code])
        try db.execute(sql:"INSERT INTO target VALUES(1,'casa'); INSERT INTO search(search) VALUES('rebuild')")
    }
    let names=[metadata.id+".json",metadata.lexiconDatabaseName,"_dictionary/search.sqlite","LICENSE.txt"]
    let files=try names.map { name -> [String:Any] in
        let data=try Data(contentsOf:folder.appendingPathComponent(name))
        return ["path":name,"byteCount":data.count,"sha256":SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()]
    }
    try JSONSerialization.data(withJSONObject:["formatVersion":1,"metadataFile":metadata.id+".json","files":files]).write(to:folder.appendingPathComponent("addon.json"))
}

@Test func aNewLanguageAddonJoinsGenerationAndEveryDictionarySearch() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer {try? FileManager.default.removeItem(at:root)}
    let selected=root.appendingPathComponent("Portuguese.lfpack");try fixtureAddon(at:selected)
    let installed=root.appendingPathComponent("installed"),installer=LanguagePackInstaller(directory:installed)
    let metadata=try await installer.install(from:selected,existingCodes:["de","ru","la","es","fr","ar","he","syc"])
    #expect(metadata.languageCode=="pt")
    let folders=try LanguagePackAddon.installedDirectories(in:installed)
    #expect(folders.count==1)
    let registry=try LanguagePackRegistry(directory:addonPacks,additionalDirectories:folders)
    #expect(registry.packs.count==9)
    #expect(try await registry.packs.first { $0.metadata.languageCode=="pt" }!.lookup(englishLemma:"house").first?.targetLemma=="casa")
    let dictionary=try OfflineDictionary(directory:addonPacks,additionalDirectories:folders)
    let groups=try await dictionary.englishTranslations("house")
    #expect(groups.count==9 && groups.first { $0.id=="pt" }!.records.first?.headword=="casa")
    let all=try await dictionary.search("house",limit:100)
    #expect(all.records.contains { $0.language=="pt" })
    #expect(Set(all.records.map(\.id)).count==all.records.count)
    let pt=try await dictionary.search("casa",language:"pt")
    #expect(try await dictionary.detail(pt.records[0]).translations==["casa"])
    await #expect(throws:DomainError.self) {try await installer.install(from:selected,existingCodes:["pt"])}
}

@Test func damagedOrLinkedAddonsNeverPublishAnInstallation() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer {try? FileManager.default.removeItem(at:root)}
    let selected=root.appendingPathComponent("bad.lfpack");try fixtureAddon(at:selected)
    let installed=root.appendingPathComponent("installed"),installer=LanguagePackInstaller(directory:installed)
    try Data("changed".utf8).write(to:selected.appendingPathComponent("LICENSE.txt"))
    await #expect(throws:DomainError.self) {try await installer.install(from:selected,existingCodes:[])}
    #expect(try LanguagePackAddon.installedDirectories(in:installed).isEmpty)
    try FileManager.default.removeItem(at:selected);try fixtureAddon(at:selected)
    let license=selected.appendingPathComponent("LICENSE.txt");try FileManager.default.removeItem(at:license)
    try FileManager.default.createSymbolicLink(at:license,withDestinationURL:root.appendingPathComponent("outside"))
    #expect(throws:DomainError.self) {try LanguagePackAddon.validate(directory:selected)}
}

@Test func latinFamiliesHaveThreeSourceLinkedLanguagesAndIndependentMeanings() async throws {
    let latin=try LatinVocabulary(databaseURL:addonPacks.appendingPathComponent("_latin/etymology.sqlite"))
    let page=try await latin.search("father")
    let family=try #require(page.families.first { $0.partOfSpeech=="noun" && $0.english=="father" })
    let members=try await latin.members(of:family.id)
    #expect(Set(members.map { $0.record.language })==["la","es","fr"])
    #expect(members.contains { $0.record.headword=="padre" })
    #expect(members.contains { $0.record.headword=="père" })
    #expect(members.filter { $0.record.language != "la" }.allSatisfy { $0.originPath.count>1 && $0.originPath.last!.hasPrefix("lat:") })
    let dictionary=try OfflineDictionary(directory:addonPacks)
    for member in members {#expect(try await dictionary.detail(member.record).senseID.isEmpty==false)}
    let first=try await latin.search("",limit:5),second=try await latin.search("",offset:5,limit:5)
    #expect(first.hasMore && Set(first.families.map(\.id)).isDisjoint(with:second.families.map(\.id)))
    #expect(try await latin.search("% ' OR 1=1 --").families.isEmpty)
}
