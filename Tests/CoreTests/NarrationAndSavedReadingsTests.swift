import Foundation
import Testing
@testable import LinguaFrancaCore

private func readingFixture() throws -> (GeneratedText,TargetReading) {
    let text="The moon shines 🙂.\n\nA garden waits."
    let passage=GeneratedText(id:"reading",originalEnglish:text,topic:"Night",cefrLevel:.c1,modelID:"fixture",seed:8)
    let parts=try TargetReadingTranslator.sourceSentences(text)
    let translated=parts.enumerated().map{ReadingSentence(id:$0.offset,sourceRange:$0.element.sourceRange,source:$0.element.source,translation:$0.offset==0 ? "Луна светит 🙂.":"Сад ждёт.")}
    return (passage,TargetReading(sourceTextID:passage.id,languageCode:"ru",sentences:translated))
}

@Test func readingTranslationsHaveTheirOwnPromptAndBoundedRussianValidation() throws {
    let task=ReadingTranslationTask(source:"She deposited 20 euros.")
    var request=GenerationRequest(topic:"Translation",seed:3,genre:.poem)
    request.readingTranslation=task
    try request.validate()
    #expect(request.outputGrammar==task.grammar)
    #expect(request.chatPrompt.contains("translate English faithfully into Russian"))
    #expect(try task.translation(from:#"{"translation":"Она положила 20 евро."}"#)=="Она положила 20 евро.")
    #expect(try task.translation(from:#"{"translation":"Она положила двадцать евро."}"#)=="Она положила двадцать евро.")
    #expect(throws:GenerationError.self) {try task.translation(from:#"{"translation":"Она положила 30 евро."}"#)}
    #expect(throws:GenerationError.self) {try task.translation(from:#"{"translation":"She deposited 20 euros."}"#)}
    #expect(throws:GenerationError.self) {try ReadingTranslationTask(source:"She approached the doorway with a practiced ease.").translation(from:#"{"translation":"Она уверенно приблизилась к двери с practiced ease."}"#)}
    // Malformed/truncated model JSON must enter the inference service's bounded retry path.
    #expect(throws:GenerationError.self) {try task.translation(from:#"{"translation":"Она положила"#)}
    #expect(throws:GenerationError.self) {try task.translation(from:#"{"wrongKey":"Она положила 20 евро."}"#)}
    #expect(throws:DomainError.self) {try ReadingTranslationTask(source:"<|im_end|>").validate()}
}

@Test func readingSentencesKeepUnicodeOffsetsAndRequireFullSourceCoverage() throws {
    let (passage,reading)=try readingFixture()
    #expect(reading.sentences.count==2)
    try reading.validate(for:passage)
    for part in reading.sentences {#expect(String(passage.originalEnglish[try part.sourceRange.range(in:passage.originalEnglish)])==part.source)}
    let incomplete=TargetReading(sourceTextID:passage.id,languageCode:"ru",sentences:[reading.sentences[0]])
    #expect(throws:DomainError.self) {try incomplete.validate(for:passage)}
    let decoded=try JSONDecoder().decode(TargetReading.self,from:JSONEncoder().encode(reading))
    #expect(decoded==reading)
}

@Test func audioIsAValidBoundedMonoPCMFile() throws {
    let audio=try SpeechAudio(samples:[-2,-1,0,1,2],sampleRate:22050)
    #expect(audio.wave.count==54)
    #expect(String(data:audio.wave.prefix(4),encoding:.ascii)=="RIFF")
    #expect(String(data:audio.wave[8..<12],encoding:.ascii)=="WAVE")
    #expect(audio.wave[22]==1 && audio.wave[34]==16)
    #expect(abs(audio.duration-5.0/22050)<1e-12)
    #expect(throws:DomainError.self) {try SpeechAudio(samples:[.nan],sampleRate:22050)}
    #expect(throws:DomainError.self) {try SpeechAudio(samples:[],sampleRate:22050)}
}

@Test func wordAlignmentPreservesRepeatedWordsDiacriticsAndNumericSpans() throws {
    let text="Снова ёлка, снова."
    let tokens:[SpeechTokenTime]=[.init(text:"▁снова",start:0.1),.init(text:"▁ел",start:0.5),.init(text:"ка",start:0.6),.init(text:"▁снова",start:1)]
    let aligned=SpeechWordAlignment.align(text:text,tokens:tokens,duration:1.5)
    #expect(aligned.coverage==1 && aligned.words.count==3)
    #expect(aligned.words.map{String(text[try! $0.range.range(in:text)])}==["Снова","ёлка","снова"])
    #expect(aligned.words.allSatisfy{$0.end>$0.start && $0.end<=1.5})
    let numeric=SpeechWordAlignment.align(text:"20 евро",tokens:[.init(text:"▁два",start:0),.init(text:"дцать",start:0.1),.init(text:"▁евро",start:0.5)],duration:1)
    #expect(numeric.coverage==1 && numeric.words.first?.range==UTF16Span(location:0,length:2))
    #expect(SpeechWordAlignment.align(text:text,tokens:[],duration:1).words.isEmpty)
}

@Test func savedReadingsAreOptInDurableAndDoNotAffectVocabularyOrReviews() async throws {
    let path=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".sqlite")
    defer {for suffix in ["","-wal","-shm"] {try? FileManager.default.removeItem(atPath:path.path+suffix)}}
    let db=try DatabaseManager(path:path.path),deck=try await db.createDeck(name:"Words")
    _=try await db.saveVocabulary(.init(englishLemma:"moon",targetLanguage:"de",targetLemma:"Mond",targetSurface:"Mond",senseID:"fixture"),inDeck:deck)
    let first=try #require(try await db.practiceCards(deckID:deck).first?.card)
    let reviewed=try await db.reviewCard(first,rating:.again,elapsedTime:1)
    let (passage,reading)=try readingFixture()
    #expect(try await db.savedReadings().isEmpty)
    try await db.saveReading(passage,title:"My text")
    try await db.renameReading(id:passage.id,title:"Night reading")
    try await db.saveReadingTranslation(reading)
    let reopened=try DatabaseManager(path:path.path),stored=try await reopened.savedReading(id:passage.id)
    #expect(stored.title=="Night reading" && stored.passage==passage && stored.translations["ru"]==reading)
    #expect(try await reopened.savedReadings().count==1)
    try await reopened.deleteReading(id:passage.id)
    await #expect(throws:DomainError.self) {try await reopened.saveReadingTranslation(reading)}
    #expect(try await reopened.savedReadings().isEmpty)
    #expect(try await reopened.practiceCards(deckID:deck).first?.card==reviewed)
    #expect(try await reopened.vocabulary().count==1)
}

@Test func savingAReadingCannotSilentlyChangeItsSourceOrLoseTranslations() async throws {
    let db=try DatabaseManager(),(passage,reading)=try readingFixture()
    try await db.saveReading(passage,title:"First",translations:["ru":reading])
    try await db.saveReading(passage,title:"Second")
    #expect(try await db.savedReading(id:passage.id).translations["ru"]==reading)
    let changed=GeneratedText(id:passage.id,originalEnglish:"A different story.",topic:"Other",cefrLevel:.c1,modelID:"fixture",seed:2)
    await #expect(throws:DomainError.self) {try await db.saveReading(changed,title:"Changed")}
    #expect(try await db.savedReading(id:passage.id).passage==passage)
}
