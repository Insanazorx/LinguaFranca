import Foundation
import Darwin
import LinguaFrancaCore
import LinguaFrancaInference

private struct Run: Codable {
    let topic: String
    let requestedLevel: String
    let requestedWordCount: Int
    let englishText: String
    let wordCount: Int
    let tokenCount: Int
    let seconds: Double
    let seed: UInt32
    let metadata: [String: String]
}

@main struct ModelSmoke {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let path = arguments.first, !path.hasPrefix("--") else {
            print("Usage: swift run model-smoke /absolute/model.gguf [--suite] [--output /absolute/report.json]")
            return
        }
        let requests: [GenerationRequest] = arguments.contains("--suite") ? [
            GenerationRequest(topic: "daily life", level: .b2, seed: 42),
            GenerationRequest(topic: "technology", level: .c1, seed: 43),
            GenerationRequest(topic: "travel", level: .c1, seed: 44)
        ] : [GenerationRequest(topic: "daily life", seed: 42)]
        let service = LlamaCppService(modelURL: URL(fileURLWithPath: path))
        var runs: [Run] = []
        do {
            for request in requests {
                let result = try await service.generate(request: request)
                let words = result.englishText.split(whereSeparator: \.isWhitespace).count
                runs.append(Run(topic: request.topic, requestedLevel: request.level.rawValue,
                    requestedWordCount: request.wordCount, englishText: result.englishText, wordCount: words,
                    tokenCount: result.tokenCount, seconds: result.duration, seed: result.seed, metadata: result.metadata))
                print("\n\(request.level.rawValue) · \(request.topic) · \(words) words · \(String(format: "%.2f", result.duration)) seconds (Mac host)")
                print(result.englishText)
            }
            await service.unloadModel()
            if let index = arguments.firstIndex(of: "--output"), arguments.indices.contains(index + 1) {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(runs).write(to: URL(fileURLWithPath: arguments[index + 1]), options: .atomic)
            }
        } catch {
            await service.unloadModel()
            throw error
        }
    }
}
