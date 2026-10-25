import Foundation
import CryptoKit
import SherpaOnnxC
import LinguaFrancaCore

public actor RussianSpeechAligner:SpeechWordAligningService {
    private let directory:URL
    private var recognizer:NativeRecognizer?
    public init(directory:URL) {self.directory=directory}
    public func unload() {recognizer=nil}
    private func load() throws {
        guard recognizer==nil else{return}
        struct Manifest:Decodable {let files:[String:String]}
        let manifest=try JSONDecoder().decode(Manifest.self,from:Data(contentsOf:directory.appendingPathComponent("ru-alignment-manifest.json")))
        let folder=directory.appendingPathComponent("ru-alignment")
        for (name,hash) in manifest.files {
            let data=try Data(contentsOf:folder.appendingPathComponent(name),options:.mappedIfSafe)
            guard SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined()==hash else {throw DomainError.invalidInput("The word-tracking model checksum does not match.")}
        }
        let strings=["encoder.int8.onnx","decoder.onnx","joiner.int8.onnx","tokens.txt"].map{strdup(folder.appendingPathComponent($0).path)!}+[strdup("cpu")!,strdup("greedy_search")!]
        defer {strings.forEach{free($0)}}
        var config=SherpaOnnxOfflineRecognizerConfig()
        config.feat_config.sample_rate=16000;config.feat_config.feature_dim=80
        config.model_config.transducer.encoder=UnsafePointer(strings[0]);config.model_config.transducer.decoder=UnsafePointer(strings[1]);config.model_config.transducer.joiner=UnsafePointer(strings[2])
        config.model_config.tokens=UnsafePointer(strings[3]);config.model_config.provider=UnsafePointer(strings[4]);config.model_config.num_threads=2
        config.decoding_method=UnsafePointer(strings[5]);config.max_active_paths=4
        guard let pointer=SherpaOnnxCreateOfflineRecognizer(&config) else {throw DomainError.invalidInput("The word-tracking model could not be loaded.")}
        recognizer=NativeRecognizer(pointer)
    }
    public func align(audio:SpeechAudio,text:String) throws -> SpeechWordAlignment {
        try Task.checkCancellation();try load()
        guard let recognizer,let stream=SherpaOnnxCreateOfflineStream(recognizer.pointer) else {throw DomainError.missingRecord}
        defer {SherpaOnnxDestroyOfflineStream(stream)}
        audio.samples.withUnsafeBufferPointer {SherpaOnnxAcceptWaveformOffline(stream,Int32(audio.sampleRate),$0.baseAddress,Int32($0.count))}
        SherpaOnnxDecodeOfflineStream(recognizer.pointer,stream)
        try Task.checkCancellation()
        guard let result=SherpaOnnxGetOfflineStreamResult(stream) else {throw DomainError.invalidInput("Word tracking could not be aligned.")}
        defer {SherpaOnnxDestroyOfflineRecognizerResult(result)}
        let count=Int(result.pointee.count)
        guard count>0,count<=2000,let words=result.pointee.tokens_arr,let times=result.pointee.timestamps else {return .align(text:text,tokens:[],duration:audio.duration)}
        let tokens=(0..<count).compactMap {index->SpeechTokenTime? in
            guard let word=words[index] else{return nil}
            return .init(text:String(cString:word),start:Double(times[index]))
        }
        return .align(text:text,tokens:tokens,duration:audio.duration)
    }
}

private final class NativeRecognizer:@unchecked Sendable {
    let pointer:OpaquePointer
    init(_ pointer:OpaquePointer){self.pointer=pointer}
    deinit {SherpaOnnxDestroyOfflineRecognizer(pointer)}
}
