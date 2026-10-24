import Foundation

public enum WritingGenre: String, Codable, CaseIterable, Sendable, Identifiable {
    case story, novel, dialogue, play, essay, poem
    public var id: Self { self }
    public var title: String {
        switch self {
        case .story: "Short story"
        case .novel: "Novel excerpt"
        case .dialogue: "Dialogue"
        case .play: "Theatre scene"
        case .essay: "Essay"
        case .poem: "Poem"
        }
    }
    public var instruction: String {
        switch self {
        case .story: "Write a short story with a concrete event and a resolution."
        case .novel: "Write a self-contained scene from a novel, with a character, vivid setting and tension."
        case .dialogue: "Write a dialogue: six alternating turns between Alex and Sam, about 12 to 18 words per turn. Start each turn on a new line with Alex: or Sam:. No narration."
        case .play: "Write a short play with Alex and Sam: six spoken turns on separate lines starting Alex: or Sam:, plus one brief stage direction in parentheses. No prose narrator."
        case .essay: "Write a short essay with a clear claim, supporting reasoning and a conclusion."
        case .poem: "Write an original poem in 8 to 12 separate lines, with concrete imagery and 5 to 10 words per line. Preserve line breaks. No title or commentary."
        }
    }
    /// Format constraints only. Every word of the actual content is still generated locally.
    public var outputGrammar: String? {
        let words = #"word ::= [A-Za-z]{1,24} (['-] [A-Za-z]{1,12})?"#
        switch self {
        case .story, .novel, .essay: return nil
        case .dialogue, .play:
            let root = self == .play ? #"root ::= "(" direction ")" "\n" turns"# : "root ::= turns"
            return root + "\n" + #"""
            turns ::= turn-a "\n" turn-b "\n" turn-a "\n" turn-b "\n" turn-a "\n" turn-b
            turn-a ::= "Alex: " sentence
            turn-b ::= "Sam: " sentence
            sentence ::= (word [;,]? " "){11,17} word [.!?]
            direction ::= (word " "){3,7} word
            """# + "\n" + words + "\n"
        case .poem:
            return #"""
            root ::= (verse "\n"){7} verse
            verse ::= (word [;,]? " "){4,8} word [.!?,;]?
            """# + "\n" + words + "\n"
        }
    }
}

public enum ReplacementMode: String, Codable, CaseIterable, Sendable {
    case balanced, aggressive
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer(), raw = try c.decode(String.self)
        if raw == "focused" { self = .aggressive }
        else if let value = Self(rawValue: raw) { self = value }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unknown replacement mode") }
    }
}

public enum PracticeDomain: String, Codable, CaseIterable, Sendable, Identifiable {
    case structure, content, actions, prepositionalPhrases
    public var id: Self { self }
    public var title: String {
        switch self { case .structure: "Sentence structure"; case .content: "Content words"; case .actions: "Verbs & verb forms"; case .prepositionalPhrases: "Preposition + object / verb" }
    }
    public var detail: String {
        switch self { case .structure: "Conjunctions · prepositions"; case .content: "Nouns · adjectives · adverbs"; case .actions: "Verbs · infinitives · participles"; case .prepositionalPhrases: "Whole phrases · governed case · nonfinite verbs" }
    }
    public func includes(_ partOfSpeech: String) -> Bool {
        switch self {
        case .structure: ["conjunction", "preposition"].contains(partOfSpeech)
        case .content: ["noun", "adjective", "adverb"].contains(partOfSpeech)
        case .actions: partOfSpeech == "verb"
        case .prepositionalPhrases: false
        }
    }
}
