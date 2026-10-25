import AVFoundation
import Observation
import LinguaFrancaCore

public enum NarrationState: Sendable, Equatable {case idle,buffering,playing,paused,failed}

/// Speech assets load only after explicit playback and are released outside active listening.
@MainActor @Observable public final class PassageNarrator: NSObject, AVAudioPlayerDelegate {
    public private(set) static weak var active:PassageNarrator?
    public private(set) var state:NarrationState = .idle
    public private(set) var reading:TargetReading?
    public private(set) var currentSentenceIndex:Int?
    public private(set) var errorMessage:String?
    public var speed:Float=0.95
    public var followWords=true {
        didSet {if !followWords {currentWordRange=nil} else {alignCurrentClip()}}
    }
    public private(set) var currentWordRange:UTF16Span?
    public private(set) var wordTrackingMessage:String?
    private let speech:any SpeechSynthesisService
    private let aligner:(any SpeechWordAligningService)?
    private var task:Task<Void,Never>?
    private var player:AVAudioPlayer?
    private var playerID:ObjectIdentifier?
    private var completion:CheckedContinuation<Bool,Never>?
    private var generation=UUID()
    private var pauseRequested=false
    private var wordTimes:[SpeechWordTime]=[]
    private var currentAudio:SpeechAudio?
    private var currentText:String?
    private var clock:Task<Void,Never>?
    private var alignmentTask:Task<Void,Never>?
    private var releaseTask:Task<Void,Never>?
    public init(speech:any SpeechSynthesisService,aligner:(any SpeechWordAligningService)?=nil) {
        self.speech=speech;self.aligner=aligner;super.init();Self.active=self
    }
    public func play(_ reading:TargetReading) {
        stop();self.reading=reading;errorMessage=nil
        let job=generation
        task=Task {
            do {
                for (index,sentence) in reading.sentences.enumerated() {
                    // A previous Stop/pause may still be releasing native handles.
                    await releaseTask?.value
                    try Task.checkCancellation()
                    guard generation==job else{return}
                    state = .buffering
                    let audio=try await speech.synthesize(text:sentence.translation,languageCode:reading.languageCode,speed:speed)
                    try Task.checkCancellation()
                    guard generation==job else{return}
                    wordTimes=[];currentWordRange=nil;wordTrackingMessage=nil
                    if followWords,let aligner {
                        if let aligned=try? await aligner.align(audio:audio,text:sentence.translation),aligned.coverage>=0.6 {wordTimes=aligned.words}
                        else {wordTrackingMessage="Word highlighting is unavailable for this sentence."}
                    }
                    try Task.checkCancellation()
                    guard generation==job else{return}
                    currentAudio=audio;currentText=sentence.translation
                    currentSentenceIndex=index
                    let played=try await playClip(audio)
                    try Task.checkCancellation()
                    guard played else {throw DomainError.invalidInput("Audio playback could not finish.")}
                }
                guard generation==job else{return}
                player=nil;playerID=nil;currentSentenceIndex=nil;currentWordRange=nil;currentAudio=nil;currentText=nil;clock?.cancel();clock=nil;state = .idle;task=nil
                deactivateAudio();releaseModels()
            } catch {
                guard generation==job else{return}
                player?.stop();player=nil;playerID=nil;currentSentenceIndex=nil;currentWordRange=nil;currentAudio=nil;currentText=nil;clock?.cancel();clock=nil;task=nil
                if error is CancellationError {state = .idle}
                else {errorMessage=error.localizedDescription;state = .failed}
                deactivateAudio();releaseModels()
            }
        }
    }
    public func pause() {
        guard state == .playing || state == .buffering else{return}
        pauseRequested=true;player?.pause();state = .paused
        alignmentTask?.cancel();alignmentTask=nil
        deactivateAudio()
        if player != nil {releaseModels()}
    }
    public func resume() {
        guard state == .paused else{return}
        do {
            try activateAudio()
            pauseRequested=false
            if let player {
                guard player.play() else {throw DomainError.invalidInput("Audio playback could not resume.")}
                state = .playing
                if followWords && wordTimes.isEmpty {alignCurrentClip()}
            } else {state = .buffering}
        } catch {errorMessage=error.localizedDescription;stop();state = .failed}
    }
    public func stop() {
        generation=UUID();task?.cancel();task=nil;pauseRequested=false
        alignmentTask?.cancel();alignmentTask=nil;clock?.cancel();clock=nil
        player?.stop();player=nil;playerID=nil
        let pending=completion;completion=nil;pending?.resume(returning:false)
        state = .idle;currentSentenceIndex=nil;currentWordRange=nil;currentAudio=nil;currentText=nil;wordTimes=[];wordTrackingMessage=nil
        deactivateAudio();releaseModels()
    }
    public func unload() async {stop();await releaseTask?.value}
    private func releaseModels() {
        let previous=releaseTask,speech=speech,aligner=aligner
        releaseTask=Task {
            await previous?.value
            await speech.unload()
            await aligner?.unload()
        }
    }
    private func activateAudio() throws {
        #if os(iOS)
        try AVAudioSession.sharedInstance().setCategory(.playback,mode:.spokenAudio)
        try AVAudioSession.sharedInstance().setActive(true)
        #endif
    }
    private func deactivateAudio() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
        #endif
    }
    private func playClip(_ audio:SpeechAudio) async throws -> Bool {
        try activateAudio()
        let clip=try AVAudioPlayer(data:audio.wave)
        player=clip;playerID=ObjectIdentifier(clip);clip.delegate=self;clip.prepareToPlay()
        clock?.cancel()
        clock=Task { [weak self] in
            while !Task.isCancelled {
                guard let self,self.playerID==ObjectIdentifier(clip) else{return}
                let range=self.followWords ? self.wordTimes.first(where:{$0.start<=clip.currentTime && clip.currentTime<$0.end})?.range:nil
                if self.currentWordRange != range {self.currentWordRange=range}
                try? await Task.sleep(for:.milliseconds(40))
            }
        }
        return await withCheckedContinuation { continuation in
            completion=continuation
            if pauseRequested {state = .paused;deactivateAudio();releaseModels()}
            else {state = .playing;if !clip.play() {finish(id:ObjectIdentifier(clip),success:false)}}
        }
    }
    private func finish(id:ObjectIdentifier,success:Bool) {
        guard playerID==id else{return}
        clock?.cancel();clock=nil;alignmentTask?.cancel();alignmentTask=nil
        let pending=completion;completion=nil;player=nil;playerID=nil
        pending?.resume(returning:success)
    }
    private func alignCurrentClip() {
        guard state == .playing,let aligner,let currentAudio,let currentText,let id=playerID else{return}
        alignmentTask?.cancel()
        alignmentTask=Task {
            let result=try? await aligner.align(audio:currentAudio,text:currentText)
            guard !Task.isCancelled,playerID==id,followWords else{return}
            if let result,result.coverage>=0.6 {wordTimes=result.words;wordTrackingMessage=nil}
            else {wordTrackingMessage="Word highlighting is unavailable for this sentence."}
        }
    }
    nonisolated public func audioPlayerDidFinishPlaying(_ player:AVAudioPlayer,successfully flag:Bool) {
        let id=ObjectIdentifier(player)
        Task {@MainActor [weak self] in self?.finish(id:id,success:flag)}
    }
    nonisolated public func audioPlayerDecodeErrorDidOccur(_ player:AVAudioPlayer,error:Error?) {
        let id=ObjectIdentifier(player)
        Task {@MainActor [weak self] in self?.finish(id:id,success:false)}
    }
}
