import Foundation
import LinguaFrancaCore
import LinguaFrancaInference

@main struct SpeechSmoke {
    static func main() async throws {
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let voice=PiperSpeechService(directory:root.appendingPathComponent("Resources/Speech"))
        let start=Date.now
        let text="Сегодня мы гуляем по тихому городу. После дождя воздух стал свежим, а над рекой появилось солнце. Я читаю интересную книгу и постепенно учусь понимать русский язык."
        let audio=try await voice.synthesize(text:text,languageCode:"ru",speed:0.95)
        try audio.wave.write(to:URL(fileURLWithPath:"/private/tmp/LinguaFranca-Russian-Denis.wav"))
        print("Denis: \(audio.duration) s audio, \(Date.now.timeIntervalSince(start)) s synthesis, \(audio.wave.count) bytes WAV")
        let aligner=RussianSpeechAligner(directory:root.appendingPathComponent("Resources/Speech"))
        let aligned=try await aligner.align(audio:audio,text:text)
        print("Word alignment: \(aligned.words.count) words, coverage \(aligned.coverage)")
        for word in aligned.words.prefix(4) {print("\(word.start)–\(word.end): "+String(text[try word.range.range(in:text)]))}
        await aligner.unload()
        await voice.unload()
        let fileIndex=CommandLine.arguments.firstIndex(of:"--reading-file")
        if CommandLine.arguments.contains("--translation-check") || fileIndex != nil {
            let descriptor=BundledModel.aggressive
            let model=LlamaCppService(modelURL:root.appendingPathComponent("Resources/Models/"+descriptor.filename),model:descriptor)
            let source="She deposited 20 euros at the bank. The children sat on the river bank. Although the road was wet, we reached the station before sunset. The manager did not cancel the meeting."
            let passage:GeneratedText
            if let fileIndex,CommandLine.arguments.indices.contains(fileIndex+1) {
                passage=try JSONDecoder().decode(GeneratedText.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[fileIndex+1])))
            } else {passage=GeneratedText(originalEnglish:source,topic:"Reading translation check",cefrLevel:.c1,modelID:descriptor.identifier,seed:9)}
            let reading=try await TargetReadingTranslator(model:model).translate(passage)
            for sentence in reading.sentences {print(sentence.source+"\n→ "+sentence.translation)}
            await model.unloadModel()
        }
    }
}
