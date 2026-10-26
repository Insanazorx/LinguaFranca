import Foundation
import Testing
import GRDB
@testable import LinguaFrancaCore

private var semiticPacks: URL { URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/LanguagePacks") }
private let writingRoots = ["ar":"كتب","he":"כתב","syc":"ܟܬܒ"]

@Test func semiticRootsAreRealSearchableAndKeepSeparateIdentities() async throws {
    let catalog=try SemiticLexicon(directory:semiticPacks)
    #expect(await catalog.availableLanguages()==["ar","he","syc"])
    var ids: Set<String> = []
    for code in ["ar","he","syc"] {
        let roots=try await catalog.roots(language:code,search:writingRoots[code]!)
        let root=try #require(roots.first { $0.native.replacingOccurrences(of:" ",with:"")==writingRoots[code] })
        ids.insert(root.id)
        #expect(root.lexemeCount>0 && root.source.hasPrefix("https://"))
        let lexemes=try await catalog.lexemes(rootID:root.id,language:code)
        #expect(!lexemes.isEmpty && lexemes.allSatisfy{$0.rootID==root.id && $0.languageCode==code})
        let forms=try await catalog.verifiedForms(for:root.reference)
        #expect(!forms.isEmpty && forms.allSatisfy{$0.status == .attested && !$0.source.isEmpty})
        #expect(try await catalog.verifiedForms(for:.init(languageCode:code,kind:.wordForm,rootID:nil,wordFormID:"missing")).isEmpty)
    }
    #expect(ids.count==3)
    let search=try await catalog.roots(language:"he",search:"katav")
    #expect(search.contains{$0.native=="כ ת ב"})
}

@Test func semiticVocabularyReusesListsAndPreservesSelectionKinds() async throws {
    let catalog=try SemiticLexicon(directory:semiticPacks),db=try DatabaseManager()
    let deck=try await db.createDeck(name:"Semitic study")
    let root=try #require(try await catalog.roots(language:"he",search:"כתב").first{$0.native=="כ ת ב"})
    let rootID=try await db.saveVocabulary(root.vocabularyDraft,inDeck:deck)
    #expect(try await db.saveVocabulary(root.vocabularyDraft,inDeck:deck)==rootID)
    let lexeme=try #require(try await catalog.lexemes(rootID:root.id,language:"he").first{$0.partOfSpeech=="verb" && $0.pattern=="Pa'al"})
    _=try await db.saveVocabulary(lexeme.vocabularyDraft,inDeck:deck)
    let form=try #require(try await catalog.verifiedForms(for:lexeme.reference).first{$0.tags.contains("past") && $0.tags.contains("first-person") && $0.tags.contains("singular")})
    _=try await db.saveVocabulary(form.vocabularyDraft(for:lexeme),inDeck:deck)
    let items=try await db.vocabulary(deckID:deck)
    #expect(items.count==3)
    #expect(Set(items.compactMap{$0.draft.lexicalReference?.kind})==[.root,.lexeme,.wordForm])
    #expect(try await db.studySummary().newCards==3)
    let registry=try LanguagePackRegistry(directory:semiticPacks)
    let requests=try await VocabularyPracticePlanner(registry:registry,semiticLexicon:catalog).batches(items:items,languageCode:"he")
    #expect(requests.count==1 && requests[0].expressions.count==3)
    #expect(requests[0].expressions.allSatisfy{!$0.lexicalForms.isEmpty})
    #expect(!requests[0].expressions.contains{$0.target==root.native})
    try await db.deleteVocabulary(id:rootID)
    #expect(try await db.vocabulary().count==2)
}

@Test func semiticMigrationKeepsOldCardsReviewsAndSettings() async throws {
    let path=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".sqlite")
    defer{for suffix in ["","-wal","-shm"]{try? FileManager.default.removeItem(atPath:path.path+suffix)}}
    let old=try DatabaseManager(path:path.path),deck=try await old.createDeck(name:"Old list")
    _=try await old.saveVocabulary(.init(englishLemma:"garden",targetLanguage:"de",targetLemma:"Garten",targetSurface:"Garten",senseID:"place",partOfSpeech:"noun"),inDeck:deck)
    var settings=AppSettings();settings.writingGenre = .play;try await old.saveSettings(settings)
    let queue=try DatabaseQueue(path:path.path)
    try await queue.write { db in
        let card=try #require(try String.fetchOne(db,sql:"SELECT id FROM srsCard"))
        try db.execute(sql:"INSERT INTO reviewLog(id,cardID,rating,reviewedAt,elapsedTime,scheduledInterval,priorState,resultingState,schedulerVersion) VALUES('historical',?,3,?,1,2,'review','review','preserved')",arguments:[card,Date.now.timeIntervalSince1970])
        try db.execute(sql:"DROP TABLE vocabularyLexicalReference; DELETE FROM grdb_migrations WHERE identifier='v3_semitic_vocabulary_references'")
    }
    let reopened=try DatabaseManager(path:path.path)
    #expect(try await reopened.vocabulary().count==1)
    #expect(try await reopened.settings()==settings)
    #expect(try await queue.read{try Int.fetchOne($0,sql:"SELECT count(*) FROM reviewLog WHERE schedulerVersion='preserved'")}==1)
    #expect(try await queue.read{try Int.fetchOne($0,sql:"SELECT count(*) FROM srsCard")}==1)
    #expect(try await queue.read{try Row.fetchAll($0,sql:"PRAGMA foreign_key_check").isEmpty})
}

@Test func unicodeMorphologyAnnotationsPreservePointedSurfacesAndOriginalOffsets() async throws {
    let catalog=try SemiticLexicon(directory:semiticPacks)
    let root=try #require(try await catalog.roots(language:"he",search:"כתב").first{$0.native=="כ ת ב"})
    let forms=try await catalog.verifiedForms(for:root.reference)
    let expression=PracticeExpression(id:"saved-root",target:"כָּתַב",english:"write",meaning:"writing",lexicalReference:root.reference,lexicalForms:forms)
    let request=VocabularyPracticeRequest(languageCode:"he",expressions:[expression])
    let text="📚 כָּתַבְתִּי מכתב."
    let result=try await VocabularyPassageAnnotator.analyze(text,request:request,lexicon:catalog)
    #expect(result.usedIDs==["saved-root"] && result.omittedIDs.isEmpty)
    let annotation=try #require(result.annotations.first)
    #expect(String(text[try annotation.range.range(in:text)])=="כָּתַבְתִּי")
    #expect(annotation.range.location==3 && annotation.range.length>5)
    #expect(SemiticUnicode.key("כָּתַבְתִּי")=="כתבתי")
    #expect(!SemiticUnicode.scriptMatches("This is an English paragraph.",language:"he"))
    #expect(try VocabularyPracticeValidator.validate("כָּתַבְתִּי מכתב.",request:request)=="כָּתַבְתִּי מכתב.")
}

private actor ForbiddenSyriacModel: TextGenerationService {
    private(set) var calls=0
    func loadModel(){}
    func generate(request:GenerationRequest) throws -> GenerationResult { calls+=1;throw DomainError.invalidInput("Syriac must not call Qwen") }
    func cancelGeneration(){}
    func unloadModel(){}
}

@Test func syriacUsesReproducibleSourceFramesAndNeverCallsTheLLM() async throws {
    let catalog=try SemiticLexicon(directory:semiticPacks),registry=try LanguagePackRegistry(directory:semiticPacks)
    let root=try #require(try await catalog.roots(language:"syc",search:"ܟܬܒ").first{$0.native=="ܟ ܬ ܒ"})
    let item=VocabularyItem(id:"saved-syriac-root",draft:root.vocabularyDraft,createdAt:.now)
    let practice=try #require(try await VocabularyPracticePlanner(registry:registry,semiticLexicon:catalog).batches(items:[item],languageCode:"syc").first)
    let model=ForbiddenSyriacModel(),service=VocabularyTextGenerator(model:model,lexicon:catalog)
    let request=GenerationRequest(topic:"Study",seed:42,vocabularyPractice:practice)
    let a=try await service.generate(request:request),b=try await service.generate(request:request)
    #expect(a.generation.englishText==b.generation.englishText)
    #expect(a.coverage.annotations.map(\.id)==b.coverage.annotations.map(\.id))
    #expect(await model.calls==0)
    #expect(a.coverage.usedIDs==[item.id] && a.coverage.omittedIDs.isEmpty)
    #expect(a.generation.metadata["contentSource"]=="attested-corpus-frame")
    #expect(a.coverage.sourceReferences.contains{$0.contains("ETCBC/syriac")})
    for annotation in a.coverage.annotations {
        #expect(String(a.generation.englishText[try annotation.range.range(in:a.generation.englishText)])==annotation.surface)
        #expect(annotation.forms.allSatisfy{$0.status == .attested && !$0.tags.isEmpty && $0.rootID==root.id})
    }
    let unsupported=VocabularyPracticeRequest(languageCode:"syc",expressions:[.init(id:"missing",target:"ܟܬܒ",english:"write",meaning:"unsupported")])
    await #expect(throws:DomainError.self) { try await ClassicalSyriacTextRealizer(lexicon:catalog).generate(request:unsupported,seed:42) }
}

@Test func allBundledLanguagesRegisterWithoutChangingOldDefaults() throws {
    let registry=try LanguagePackRegistry(directory:semiticPacks)
    #expect(Set(registry.packs.map{$0.metadata.languageCode})==["de","ru","ar","he","syc","la","es","fr"])
    #expect(AppSettings().enabledLanguages==["de","ru"])
    let old=#"{"sourceTextID":"x","id":"old","originalUTF16Range":{"location":0,"length":4},"renderedUTF16Range":{"location":0,"length":4},"originalSurface":"book","originalLemma":"book","originalPartOfSpeech":"noun","sourceSenseID":"old","targetLanguageCode":"de","targetLemma":"Buch","targetSurface":"Buch","translationConfidence":1,"languagePackVersion":"old"}"#
    #expect(try JSONDecoder().decode(ReplacementSpan.self,from:Data(old.utf8)).lexicalReference==nil)
}

private struct VerifiedWritingPack: LanguagePack {
    let base: SQLiteLanguagePack
    let lexemeID: String
    var metadata: LanguagePackMetadata { base.metadata }
    func lookup(englishLemma: String) async throws -> [LexicalEntry] { try await base.lookup(englishLemma:englishLemma).filter{$0.senseID==lexemeID} }
    func lookupSense(englishLemma: String,senseID: String) async throws -> LexicalEntry? { try await lookup(englishLemma:englishLemma).first{$0.senseID==senseID} }
    func inflect(_ entry: LexicalEntry,features:[String:String]) async throws -> String? { try await base.inflect(entry,features:features) }
    func validateReplacement(_ entry:LexicalEntry,surface:String,context:String) async throws -> Bool { await base.validateReplacement(entry,surface:surface,context:context) }
    func supportsPartOfSpeech(_ pos:String)->Bool { pos=="verb" }
}

@Test func semiticAdaptersReplaceVerifiedPastFormsWithoutDuplicatingTheEnglishSubject() async throws {
    let catalog=try SemiticLexicon(directory:semiticPacks)
    for (code,pattern,expected) in [("ar","I","كتبت"),("he","Pa'al","כתבתי"),("syc","Pe'al","ܟܬܒܬ")] {
        let root=try #require(try await catalog.roots(language:code,search:writingRoots[code]!).first{$0.native.replacingOccurrences(of:" ",with:"")==writingRoots[code]})
        let lexeme=try #require(try await catalog.lexemes(rootID:root.id,language:code).first{$0.partOfSpeech=="verb" && $0.pattern==pattern && SemiticUnicode.key($0.lemma)==writingRoots[code]})
        let base=try SQLiteLanguagePack(manifestURL:semiticPacks.appendingPathComponent("en-"+code+".json"))
        let pack=VerifiedWritingPack(base:base,lexemeID:lexeme.id)
        let registry=try LanguagePackRegistry(packs:[pack],englishModelDirectory:semiticPacks.appendingPathComponent("_english"))
        var settings=AppSettings();settings.enabledLanguages=[code];settings.replacementMode = .aggressive;settings.practiceDomains=[.actions]
        let source="Yesterday, I wrote a letter."
        let result=try await ContextualReplacementEngine(registry:registry).replace(text:source,sourceTextID:code,settings:settings,seed:42)
        #expect(result.isComplete,"\(code): \(result.unresolved.map(\.surface))")
        let span=try #require(result.spans.first)
        #expect(span.originalSurface=="wrote" && SemiticUnicode.key(span.targetSurface)==expected)
        #expect(span.lexicalReference?.lexemeID==lexeme.id && span.lexicalReference?.rootID==root.id)
        let reading=GeneratedText(id:code,originalEnglish:source,topic:"Test",cefrLevel:.b2,modelID:"verified-fixture",seed:42,replacements:result.spans)
        #expect(try reading.renderedText().contains("Yesterday, I "))
        #expect(String(source[try span.originalUTF16Range.range(in:source)])=="wrote")
        let entry=try #require(try await pack.lookup(englishLemma:"write").first)
        #expect(try await pack.inflect(entry,features:["form":"finite","tense":"unverified","person":"1","number":"singular"])==nil)
    }
}
