import Foundation

public struct GenerationScenario: Sendable, Equatable {
    public let id: Int
    public let situation: String
    public let focus: String
    public let perspective: String
}

public struct PassageFingerprint: Sendable, Equatable {
    let normalized: String
    let opening: String
    let phrases: Set<String>
    let contentWords: Set<String>
    public init(_ text: String) {
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        normalized = words.joined(separator: " ")
        opening = words.prefix(8).joined(separator: " ")
        phrases = words.count < 4 ? [] : Set((0...(words.count - 4)).map { words[$0..<($0 + 4)].joined(separator: " ") })
        let stop = Set("the a an and or but to of in on at by for with from as is was were be been being it its that this their they she he his her we our i my you your had has have would could should can will not which who when where then than so into while after before".split(separator: " ").map(String.init))
        contentWords = Set(words.filter { $0.count > 2 && !stop.contains($0) })
    }
}

public enum PassageNoveltyValidator {
    public static func validate(_ text: String, previous: [PassageFingerprint]) throws {
        let candidate = PassageFingerprint(text)
        for old in previous {
            let shared = candidate.phrases.intersection(old.phrases).count
            let phraseUnion = candidate.phrases.union(old.phrases).count
            let wordUnion = candidate.contentWords.union(old.contentWords).count
            let sharedWords = candidate.contentWords.intersection(old.contentWords).count
            if candidate.normalized == old.normalized
                || (!candidate.opening.isEmpty && candidate.opening == old.opening)
                || (shared >= 8 && Double(shared) / Double(max(1, phraseUnion)) > 0.3)
                || (sharedWords >= 12 && Double(sharedWords) / Double(max(1, wordUnion)) > 0.75) {
                throw GenerationError.invalidOutput("too similar to an earlier passage in this session")
            }
        }
    }
}

/// Deliberately not Codable: readings and novelty history live only for this process lifetime.
public struct ReadingSession: Sendable {
    public private(set) var passages: [GeneratedText] = []
    public private(set) var fingerprints: [PassageFingerprint] = []
    private var usedScenarios: Set<Int> = []
    private var usedSituations: Set<Int> = []
    public init() {}

    /// Retries of one Generate action remain available internally, with one visible card.
    public var visiblePassages: [GeneratedText] {
        var seen: Set<String> = []
        return passages.compactMap { passage in
            let group = passage.metadata["generationGroupID"] ?? passage.id
            guard seen.insert(group).inserted else { return nil }
            return passages.first { ($0.metadata["generationGroupID"] ?? $0.id) == group && $0.metadata["replacementComplete"] == "true" } ?? passage
        }
    }

    public mutating func nextScenario(seed: UInt32) throws -> GenerationScenario {
        let situations = ["repairing a broken everyday object", "an unexpected discovery outdoors", "a delayed journey", "preparing a small community event", "a disagreement between neighbours", "learning a skill from an older person", "recovering a misplaced possession", "an unfamiliar task at work", "a change to a household routine", "an observation that challenges a belief", "a shared meal with an unexpected guest", "a difficult choice with limited resources"]
        let focuses = ["a practical mistake and its consequences", "a small act of courage", "conflicting needs and a compromise", "an assumption disproved by evidence", "a useful idea that initially fails", "a responsibility passed to someone else", "an unexpected cost", "a quiet success achieved through patience"]
        let perspectives = ["third-person past tense", "first-person past tense", "two people with different priorities", "a newcomer noticing unfamiliar details", "someone reconsidering an earlier decision", "an observer describing a change over one day"]
        let total = situations.count * focuses.count * perspectives.count
        let available = (0..<total).filter { !usedScenarios.contains($0) }
        guard !available.isEmpty else { throw GenerationError.invalidOutput("this session has used all available story situations; reopen the app to start a new session") }
        var freshSituations = available.filter { !usedSituations.contains($0 % situations.count) }
        if freshSituations.isEmpty {
            usedSituations.removeAll()
            freshSituations = available
        }
        var rng = SeededGenerator(seed: UInt64(seed))
        let index = freshSituations[Int(rng.next() % UInt64(freshSituations.count))]
        usedScenarios.insert(index)
        usedSituations.insert(index % situations.count)
        return GenerationScenario(id: index, situation: situations[index % situations.count],
            focus: focuses[(index / situations.count) % focuses.count], perspective: perspectives[index / (situations.count * focuses.count)])
    }

    public mutating func append(_ passage: GeneratedText) throws {
        _ = try passage.renderedText()
        try PassageNoveltyValidator.validate(passage.originalEnglish, previous: fingerprints)
        guard !passages.contains(where: { $0.id == passage.id }) else { throw DomainError.invalidInput("This reading is already in the session.") }
        passages.insert(passage, at: 0)
        fingerprints.append(PassageFingerprint(passage.originalEnglish))
    }

    public mutating func remix(_ passage: GeneratedText) throws {
        _ = try passage.renderedText()
        guard let index = passages.firstIndex(where: { $0.id == passage.id }),
              passages[index].originalEnglish == passage.originalEnglish else {
            throw DomainError.invalidInput("A session reading's English original cannot be changed.")
        }
        passages[index] = passage
    }
}
