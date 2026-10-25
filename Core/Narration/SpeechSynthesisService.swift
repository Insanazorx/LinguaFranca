import Foundation

public protocol SpeechSynthesisService: Sendable {
    func synthesize(text: String, languageCode: String, speed: Float) async throws -> SpeechAudio
    func unload() async
}

public struct SpeechAudio: Sendable {
    public let wave: Data
    public let duration: TimeInterval
    public let samples:[Float]
    public let sampleRate:Int
    public init(samples: [Float], sampleRate: Int) throws {
        guard (8000...96000).contains(sampleRate), !samples.isEmpty,
              samples.count <= sampleRate * 180, samples.allSatisfy(\.isFinite) else {
            throw DomainError.invalidInput("Invalid synthesized audio.")
        }
        var data = Data()
        func ascii(_ text: String) { data.append(contentsOf: text.utf8) }
        func u16(_ n: UInt16) { var value=n.littleEndian; withUnsafeBytes(of:&value) {data.append(contentsOf:$0)} }
        func u32(_ n: UInt32) { var value=n.littleEndian; withUnsafeBytes(of:&value) {data.append(contentsOf:$0)} }
        let bytes = UInt32(samples.count * 2)
        ascii("RIFF"); u32(36+bytes); ascii("WAVEfmt "); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate*2)); u16(2); u16(16); ascii("data"); u32(bytes)
        for sample in samples {
            let pcm = Int16((max(-1,min(1,sample))*32767).rounded())
            u16(UInt16(bitPattern:pcm))
        }
        self.wave=data; self.duration=Double(samples.count)/Double(sampleRate);self.samples=samples;self.sampleRate=sampleRate
    }
}

public struct SpeechVoiceManifest: Codable, Sendable {
    public let languageCode, voiceName, identifier, modelFilename, modelSHA256: String
    public let modelByteCount: Int64
    public let sampleRate: Int
}
