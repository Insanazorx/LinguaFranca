import Foundation
import LinguaFrancaCore

struct Run: Codable {
    let profile: String
    let original: String
    let rendered: String
    let requestedDensity: Double
    let actualDensity: Double
    let wordCount: Int
    let languageCounts: [String:Int]
    let replacements: [ReplacementSpan]
}

@main struct ReplacementSmoke {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 4 else {
            print("Usage: replacement-smoke /path/to/LanguagePacks /path/to/english.txt /path/to/report.json")
            return
        }
        let registry = try LanguagePackRegistry(directory:URL(fileURLWithPath:args[1]))
        let engine = ContextualReplacementEngine(registry:registry)
        let original = try String(contentsOfFile:args[2],encoding:.utf8)
        var runs:[Run] = []
        for (name,frequency) in [("Gentle",0.05),("Medium",0.1),("Psycho",0.5)] {
            var settings = AppSettings()
            settings.enabledLanguages = registry.packs.map { $0.metadata.languageCode }
            settings.languageFrequencies = Dictionary(uniqueKeysWithValues:settings.enabledLanguages.map { ($0,frequency) })
            let mix = try await engine.replace(text:original,sourceTextID:"local-model-reading",settings:settings,seed:42)
            let passage = GeneratedText(id:"local-model-reading",originalEnglish:original,topic:"Actual local generation",
                cefrLevel:.c1,modelID:"Qwen3.5-0.8B-Q4_K_M",seed:42,replacements:mix.spans)
            runs.append(Run(profile:name,original:original,rendered:try passage.renderedText(),requestedDensity:mix.requestedDensity,
                actualDensity:mix.actualDensity,wordCount:mix.wordCount,languageCounts:mix.languageCounts,replacements:mix.spans))
            print("\(name): \(mix.spans.count)/\(mix.wordCount), \(mix.languageCounts)")
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]
        try encoder.encode(runs).write(to:URL(fileURLWithPath:args[3]),options:.atomic)
    }
}
