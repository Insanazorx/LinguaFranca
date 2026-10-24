import Foundation
import Testing
@testable import LinguaFrancaCore

@Test func internationalLookalikesStayInEnglish() {
    for (source, target) in [("information", "информация"), ("concept", "концепция"), ("strategy", "стратегия"),
        ("university", "университет"), ("culture", "культура"), ("technology", "технология"), ("problem", "пробле́ма"),
        ("music", "музыка"), ("computer", "компьютер"), ("organization", "организация"),
        ("motivation", "мотивация"), ("communication", "коммуникация"), ("emotion", "эмоция"),
        ("rationality", "рациона́льность"), ("philosophy", "философия"), ("psychology", "психология"),
        ("situation", "ситуация"), ("class", "класс"), ("system", "система"), ("chance", "шанс"),
        ("information", "Information"), ("culture", "Kultur"), ("hunger", "Hunger"), ("student", "Student") ] {
        #expect(!LexicalContrastPolicy.isDistinct(english: source, target: target), "\(source) / \(target)")
    }
}

@Test func distinctVocabularyAndUnicodeArePreserved() {
    for (source, target) in [("knowledge", "Wissen"), ("decision", "решение"), ("meaning", "Bedeutung"),
        ("effort", "усилие"), ("journey", "пое́здка"), ("tree", "Baum"), ("book", "Buch"),
        ("and", "und"), ("he", "er"), ("path", "путь"), ("responsibility", "ответственность"), ("honesty", "честность")] {
        #expect(LexicalContrastPolicy.isDistinct(english: source, target: target), "\(source) / \(target)")
    }
    #expect(!LexicalContrastPolicy.isDistinct(english: "Straße", target: "STRASSE"))
    #expect(!LexicalContrastPolicy.isDistinct(english: "café", target: "Cafe\u{301}"))
}

private var languageDirectory: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/LanguagePacks")
}

@Test func actualPacksNeverRenderTransparentPairs() async throws {
    let engine = ContextualReplacementEngine(registry: try LanguagePackRegistry(directory: languageDirectory))
    var settings = AppSettings(); settings.languageFrequencies = ["de": 0.5, "ru": 0.5]
    let text = "The university shared information about technology and culture. Knowledge requires effort and a choice. Rationality helped her overcome fear."
    let result = try await engine.replace(text: text, sourceTextID: "contrast", settings: settings, seed: 42)
    #expect(!result.spans.isEmpty)
    #expect(result.spans.allSatisfy { LexicalContrastPolicy.isDistinct(english: $0.originalLemma, target: $0.targetLemma) })
    #expect(!result.spans.contains { $0.originalLemma == "information" && $0.targetLemma.lowercased().hasPrefix("информ") })
    #expect(!result.spans.contains { $0.originalLemma == "rationality" && $0.targetLemma.lowercased().hasPrefix("рацион") })
}

@Test func promptHintsComeFromEnabledRealPacks() async throws {
    let registry = try LanguagePackRegistry(directory: languageDirectory)
    let planner = GenerationVocabularyPlanner(registry: registry)
    var settings = AppSettings()
    let hints = try await planner.hints(topic: "Education", settings: settings, seed: 42)
    #expect(Set(hints.map(\.languageCode)) == ["de", "ru"])
    #expect(try await planner.hints(topic: "Education", settings: settings, seed: 42) == hints)
    for hint in hints {
        let pack = try #require(registry.packs.first { $0.metadata.languageCode == hint.languageCode })
        #expect(try await pack.lookup(englishLemma: hint.englishLemma).contains {
            $0.partOfSpeech == "noun" && LexicalContrastPolicy.isDistinct(english: hint.englishLemma, target: $0.targetLemma)
        })
    }
    settings.enabledLanguages = []
    #expect(try await planner.hints(topic: "Education", settings: settings, seed: 42).isEmpty)
}
