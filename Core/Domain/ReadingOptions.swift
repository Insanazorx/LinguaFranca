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
        case .dialogue: "Write a natural everyday conversation between Alex and Sam in six alternating turns. Give them a practical reason to talk: ask, respond, clarify and agree on something. Keep each turn brief and conversational. Use contractions, short reactions and varied turn lengths; each reply must respond to the previous speaker. Start each turn on a new line with Alex: or Sam:. Spoken English only, no narration or essay-like monologues."
        case .play: "Write a playable theatre scene: begin with one brief, complete stage-direction sentence in parentheses, then six alternating Alex: and Sam: turns on separate lines. Give the characters a small conflict and let their actions and spoken replies resolve it. Distinguish this performed scene from a prose story. No prose narrator."
        case .essay: "Write a short essay with a clear claim, supporting reasoning and a conclusion."
        case .poem: "Write an original lyric poem in eight verse lines. Develop a recurring sensory image and an emotional turn, with a musical cadence and some thoughts flowing across line breaks. Use concrete details and natural words; rhyme is optional. This must feel like poetry, not a chronological diary, a report or eight unrelated prose sentences. No title, speaker labels, bullet points or commentary."
        }
    }
    /// Constrains the layout, not a word count or a sentence template. The same
    /// structure is used inside Aggressive's JSON English field (escaped newlines).
    public var outputGrammar: String? {
        guard let rules = formatGrammar(jsonEscaped: false) else { return nil }
        return "root ::= formatted\n" + rules
    }
    public var jsonEnglishGrammar: String? {
        guard let rules = formatGrammar(jsonEscaped: true) else { return nil }
        return #"english ::= "\"" formatted "\"""# + "\n" + rules
    }
    private func formatGrammar(jsonEscaped: Bool) -> String? {
        let newline = jsonEscaped ? #""\\n""# : #""\n""#
        // Flexible lexical units prevent a character limit from cutting a word
        // in half. A reply can be as short as Yes! or contain two sentences.
        let words = #"""
        word ::= clock | [$£€]? [A-Za-z0-9]{1,28} ([’'-] [A-Za-z0-9]{1,24}){0,2}
        clock ::= [0-9]{1,2} ":" [0-9]{2}
        """#
        switch self {
        case .story, .novel, .essay: return nil
        case .dialogue, .play:
            let turns = ["turn-a", "turn-b", "turn-a", "turn-b", "turn-a", "turn-b"].joined(separator: " " + newline + " ")
            let first = self == .play ? "formatted ::= \"(\" direction \")\" " + newline + " " + turns : "formatted ::= " + turns
            return first + "\n" + #"""
            turn-a ::= "Alex: " speech
            turn-b ::= "Sam: " speech
            speech ::= sentence (" " sentence)?
            sentence ::= (word separator){0,22} word [.!?]
            separator ::= " " | ", " | "; "
            direction ::= (word " "){2,15} word "."
            """# + "\n" + words + "\n"
        case .poem:
            return "formatted ::= " + Array(repeating: "verse", count: 8).joined(separator: " " + newline + " ") + "\n"
                + #"verse ::= (word [,;:]? " "){1,15} word [.!?,;]?"# + "\n" + words + "\n"
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
