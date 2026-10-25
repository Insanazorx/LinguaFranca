import Foundation
import CryptoKit
import SherpaOnnxC
import LinguaFrancaCore

/// A single bounded CPU voice instance. Native synthesis runs on the worker actor.
public actor PiperSpeechService: SpeechSynthesisService {
    private let worker: PiperWorker
    public init(directory: URL) { worker=PiperWorker(directory:directory) }
    public func unload() async { await worker.unload() }
    public func synthesize(text: String, languageCode: String, speed: Float = 1) async throws -> SpeechAudio {
        let cancel = SpeechCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await worker.synthesize(text:text,languageCode:languageCode,speed:speed,cancellation:cancel)
        } onCancel: { cancel.cancel() }
    }
}

private final class SpeechCancellation: @unchecked Sendable {
    private let lock=NSLock()
    private var cancelled=false
    func cancel() {lock.lock();cancelled=true;lock.unlock()}
    var isCancelled:Bool {lock.lock();defer{lock.unlock()};return cancelled}
}

private final class NativeVoice: @unchecked Sendable {
    let pointer:OpaquePointer
    init(_ pointer:OpaquePointer) {self.pointer=pointer}
    deinit {SherpaOnnxDestroyOfflineTts(pointer)}
}

private actor PiperWorker {
    let directory:URL
    private var voice:NativeVoice?
    private var loadedLanguage:String?
    init(directory:URL) {self.directory=directory}
    func unload() {voice=nil;loadedLanguage=nil}
    private func load(languageCode:String) throws {
        if voice != nil && loadedLanguage==languageCode {return}
        unload()
        let manifest=try JSONDecoder().decode(SpeechVoiceManifest.self,from:Data(contentsOf:directory.appendingPathComponent(languageCode+"-manifest.json")))
        let folder=directory.appendingPathComponent(languageCode),model=folder.appendingPathComponent(manifest.modelFilename)
        let tokens=folder.appendingPathComponent("tokens.txt"),data=folder.appendingPathComponent("espeak-ng-data")
        guard manifest.languageCode==languageCode, (8000...96000).contains(manifest.sampleRate),
              (try model.resourceValues(forKeys:[.fileSizeKey]).fileSize)==Int(manifest.modelByteCount),
              FileManager.default.fileExists(atPath:tokens.path),FileManager.default.fileExists(atPath:data.path) else {
            throw DomainError.invalidInput("The bundled Russian voice is missing.")
        }
        let digest=SHA256.hash(data:try Data(contentsOf:model,options:.mappedIfSafe)).map{String(format:"%02x",$0)}.joined()
        guard digest==manifest.modelSHA256 else {throw DomainError.invalidInput("The Russian voice checksum does not match.")}
        let strings=[model.path,tokens.path,data.path,"cpu"].map{strdup($0)!}
        defer {strings.forEach{free($0)}}
        var config=SherpaOnnxOfflineTtsConfig()
        config.model.vits.model=UnsafePointer(strings[0]); config.model.vits.tokens=UnsafePointer(strings[1]); config.model.vits.data_dir=UnsafePointer(strings[2])
        config.model.vits.noise_scale=0.667; config.model.vits.noise_scale_w=0.8; config.model.vits.length_scale=1
        config.model.num_threads=2; config.model.provider=UnsafePointer(strings[3]);config.max_num_sentences=1;config.silence_scale=0.2
        guard let pointer=SherpaOnnxCreateOfflineTts(&config) else {throw DomainError.invalidInput("The Russian speech model could not be loaded.")}
        voice=NativeVoice(pointer)
        loadedLanguage=languageCode
    }
    func synthesize(text:String,languageCode:String,speed:Float,cancellation:SpeechCancellation) throws -> SpeechAudio {
        guard (2...3).contains(languageCode.count),languageCode.allSatisfy({$0.isASCII && $0.isLowercase && $0.isLetter}), speed.isFinite,(0.65...1.35).contains(speed),
              !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, text.count<=1400,
              !text.contains("\0") else {throw DomainError.invalidInput("Unsupported speech request.")}
        guard !cancellation.isCancelled else {throw CancellationError()}
        try load(languageCode:languageCode)
        guard let voice else {throw DomainError.missingRecord}
        var config=SherpaOnnxGenerationConfig();config.sid=0;config.speed=speed;config.silence_scale=0.2
        let user=Unmanaged.passUnretained(cancellation).toOpaque()
        guard let audio=text.withCString({SherpaOnnxOfflineTtsGenerateWithConfig(voice.pointer,$0,&config,{_,_,_,arg in
            guard let arg else{return 0}
            return Unmanaged<SpeechCancellation>.fromOpaque(arg).takeUnretainedValue().isCancelled ? 0:1
        },user)}) else {throw DomainError.invalidInput("Russian speech generation failed.")}
        defer {SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio)}
        guard !cancellation.isCancelled else {throw CancellationError()}
        guard audio.pointee.n>0,let samples=audio.pointee.samples else {throw DomainError.invalidInput("The voice returned no audio.")}
        return try SpeechAudio(samples:Array(UnsafeBufferPointer(start:samples,count:Int(audio.pointee.n))),sampleRate:Int(audio.pointee.sample_rate))
    }
}
