import Foundation
import Testing
import LinguaFrancaCore
import LinguaFrancaInference

private actor WaitingSpeech:SpeechSynthesisService {
    private let started:AsyncStream<Void>.Continuation
    private(set) var requests=0
    private(set) var cancellations=0
    private(set) var releases=0
    init(started:AsyncStream<Void>.Continuation) {self.started=started}
    func synthesize(text:String,languageCode:String,speed:Float) async throws -> SpeechAudio {
        requests+=1;started.yield()
        do {try await Task.sleep(for:.seconds(60))}
        catch {cancellations+=1;started.yield();throw error}
        return try SpeechAudio(samples:[0],sampleRate:22050)
    }
    func unload() {releases+=1}
}
private actor AlignmentReleaseSpy:SpeechWordAligningService {
    private(set) var releases=0
    func align(audio:SpeechAudio,text:String) -> SpeechWordAlignment {.align(text:text,tokens:[],duration:1)}
    func unload() {releases+=1}
}

@Test @MainActor func speechRemainsOffUntilExplicitPlaybackAndStopReleasesResources() async {
    let signal=AsyncStream<Void>.makeStream()
    let speech=WaitingSpeech(started:signal.continuation),aligner=AlignmentReleaseSpy()
    let narrator=PassageNarrator(speech:speech,aligner:aligner)
    #expect(await speech.requests==0)
    #expect(await speech.releases==0)
    let sentence=ReadingSentence(id:0,sourceRange:.init(location:0,length:5),source:"Hello",translation:"Привет")
    narrator.play(.init(sourceTextID:"lifecycle",languageCode:"ru",sentences:[sentence,sentence]))
    var events=signal.stream.makeAsyncIterator()
    _=await events.next()
    narrator.stop()
    _=await events.next()
    await narrator.unload()
    #expect(narrator.state == .idle)
    #expect(await speech.requests==1) // No later sentence starts after cancellation.
    #expect(await speech.cancellations==1)
    #expect(await speech.releases>=2)
    #expect(await aligner.releases>=2)
    signal.continuation.finish()
}
