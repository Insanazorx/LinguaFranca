import Foundation

public struct GenerationVocabularyHint: Sendable, Equatable {
    public let englishLemma: String
    public let languageCode: String
    public init(englishLemma: String, languageCode: String) {
        self.englishLemma = englishLemma; self.languageCode = languageCode
    }
}

/// English topic pools guide content; every hint also needs a real local dictionary entry.
public struct GenerationVocabularyPlanner: Sendable {
    private let registry: LanguagePackRegistry
    public init(registry: LanguagePackRegistry) { self.registry = registry }

    public func hints(topic: String, settings: AppSettings, seed: UInt32) async throws -> [GenerationVocabularyHint] {
        try settings.validate()
        let general = ["knowledge", "skill", "effort", "purpose", "doubt", "evidence", "habit", "burden", "reward", "choice", "growth", "shortage", "advice", "trust", "achievement", "understanding"]
        let pools: [String: [String]] = [
            "Daily life": ["neighbour", "household", "meal", "shelter", "garden", "belonging", "errand", "waste"],
            "Work and careers": ["wage", "workload", "deadline", "livelihood", "craft", "leadership", "workplace", "duty"],
            "Technology": ["device", "tool", "shortcut", "failure", "ownership", "drawback", "breakthrough", "privacy"],
            "Science": ["evidence", "discovery", "research", "measurement", "trial", "finding", "doubt", "wildlife"],
            "Psychology": ["behaviour", "fear", "belief", "awareness", "thought", "mood", "kindness", "wellbeing"],
            "Society": ["wealth", "poverty", "fairness", "neighbourhood", "law", "safety", "trust", "livelihood"],
            "Travel": ["journey", "luggage", "path", "shelter", "border", "delay", "landscape", "fare"],
            "Literature": ["tale", "plot", "meaning", "reader", "belief", "doubt", "insight", "fate"],
            "Education": ["knowledge", "skill", "learning", "teacher", "homework", "understanding", "effort", "achievement"],
            "Culture": ["heritage", "custom", "craft", "gathering", "belonging", "tale", "belief", "celebration"]
        ]
        var result: [GenerationVocabularyHint] = [], rng = SeededGenerator(seed: UInt64(seed))
        for pack in registry.packs where (settings.replacementLanguageShares[pack.metadata.languageCode] ?? 0) > 0 {
            var candidates = pools[topic] ?? general; candidates.shuffle(using: &rng)
            var fallback = general; fallback.shuffle(using: &rng)
            var seen: Set<String> = [], count = 0
            for lemma in candidates + fallback where seen.insert(lemma).inserted {
                try Task.checkCancellation()
                let entries = try await pack.lookup(englishLemma: lemma)
                if entries.contains(where: {
                    $0.partOfSpeech == "noun" && !$0.provenance.isEmpty
                        && LexicalContrastPolicy.isDistinct(english: lemma, target: $0.targetLemma)
                        && !["obsolete", "archaic", "vulgar", "slang", "rare"].contains(where: ($0.morphologicalTags["definition"] ?? "").lowercased().contains)
                }) {
                    result.append(GenerationVocabularyHint(englishLemma: lemma, languageCode: pack.metadata.languageCode))
                    count += 1
                    if count == 3 { break }
                }
            }
        }
        return result
    }
}
