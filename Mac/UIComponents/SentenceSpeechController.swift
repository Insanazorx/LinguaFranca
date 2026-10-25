import AVFoundation
import Observation
import LinguaFrancaInference
import LinguaFrancaCore

@MainActor @Observable final class SentenceSpeechController: NSObject, AVSpeechSynthesizerDelegate {
    static weak var active:SentenceSpeechController?
    private let synthesizer = AVSpeechSynthesizer()
    private var pending: Set<ObjectIdentifier> = []
    private(set) var isSpeaking = false
    private(set) var errorMessage: String?

    override init() {
        super.init()
        synthesizer.delegate = self
    }
    static func hasLocalVoice(_ language: String) -> Bool {
        guard language != "syc" else { return false }
        return AVSpeechSynthesisVoice.speechVoices().contains { !$0.voiceTraits.contains(.isNoveltyVoice) && $0.language.split(separator:"-").first.map(String.init)==language }
    }

    func speak(_ segments: [SentenceSpeechSegment]) {
        if Self.active !== self {Self.active?.stop()}
        Self.active=self
        PassageNarrator.active?.pause()
        stop()
        errorMessage = nil
        // speechVoices enumerates voices available on this device. Never initiate a download.
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { !$0.voiceTraits.contains(.isNoveltyVoice) }.sorted {
            $0.quality.rawValue == $1.quality.rawValue ? $0.identifier < $1.identifier : $0.quality.rawValue < $1.quality.rawValue
        }
        let spoken = segments.filter { $0.text.contains(where: { $0.isLetter || $0.isNumber }) }
        var utterances: [AVSpeechUtterance] = []
        for segment in spoken {
            guard let voice = voices.first(where: { $0.language.split(separator: "-").first.map(String.init) == segment.languageCode }) else {
                let name = Locale(identifier: "en").localizedString(forLanguageCode: segment.languageCode) ?? segment.languageCode
                errorMessage = "A local \(name) voice is unavailable on this device."
                return
            }
            let utterance = AVSpeechUtterance(string: segment.text)
            utterance.voice = voice
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.86
            utterance.postUtteranceDelay = 0.025
            utterances.append(utterance)
        }
        guard !utterances.isEmpty else { return }
        pending = Set(utterances.map(ObjectIdentifier.init))
        isSpeaking = true
        for utterance in utterances { synthesizer.speak(utterance) }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        pending.removeAll(); isSpeaking = false
    }
    private func finished(_ id: ObjectIdentifier) {
        guard pending.remove(id) != nil else { return }
        if pending.isEmpty {
            isSpeaking = false
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finished(id) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finished(id) }
    }
}
