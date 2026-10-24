import AVFoundation
import Observation
import LinguaFrancaCore

@MainActor @Observable final class SentenceSpeechController: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var pending: Set<ObjectIdentifier> = []
    private(set) var isSpeaking = false
    private(set) var errorMessage: String?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ segments: [SentenceSpeechSegment]) {
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
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            pending = Set(utterances.map(ObjectIdentifier.init))
            isSpeaking = true
            for utterance in utterances { synthesizer.speak(utterance) }
        } catch { errorMessage = "Pronunciation could not start: \(error.localizedDescription)" }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        pending.removeAll(); isSpeaking = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    private func finished(_ id: ObjectIdentifier) {
        guard pending.remove(id) != nil else { return }
        if pending.isEmpty {
            isSpeaking = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
