import Foundation

/// Selects only source-published forms. No root-pattern synthesis or guessed endings.
enum SemiticMorphologyAdapter {
    static func surface(forms: [SemiticWordForm], entry: LexicalEntry, features: [String:String], language: String) -> String? {
        var candidates=forms.filter { $0.status == .attested }
        func require(_ tag: String) { candidates.removeAll { !$0.tags.contains(tag) } }
        if entry.partOfSpeech == "verb" {
            guard let form=features["form"] else { return nil }
            switch form {
            case "infinitive": require("infinitive")
            case "pastParticiple": require("participle"); require("passive")
            case "finite":
                guard let tense=features["tense"], let number=features["number"], let person=features["person"] else { return nil }
                let personTag=["1":"first-person","2":"second-person","3":"third-person"][person]!
                require(number)
                if tense == "past" { require(language == "syc" ? "perfect" : "past"); require(personTag) }
                else if tense == "present" {
                    if language == "he" { require("present") }
                    else if language == "ar" { require("indicative"); require("non-past"); require(personTag) }
                    else { require("participle"); require("active") }
                } else { return nil }
                if let gender=features["gender"] { require(gender) }
                else if (language == "he" && tense == "present") || person != "1" { return nil }
                candidates.removeAll { $0.tags.contains("passive") || $0.tags.contains("imperative") || $0.tags.contains("negative") }
            default: return nil
            }
        } else if entry.partOfSpeech == "adjective" {
            guard features["form"] == "predicative", let gender=features["gender"] else { return nil }
            require(gender); if let number=features["number"] { require(number) }
        } else if entry.partOfSpeech == "noun", features["number"] == "plural" {
            require("plural")
            candidates.removeAll { $0.tags.contains("possessed-form") || $0.tags.contains("construct") || $0.tags.contains("accusative") || $0.tags.contains("genitive") }
        } else {
            return forms.first(where: { $0.tags.contains("canonical") && SemiticUnicode.key($0.surface)==SemiticUnicode.key(entry.targetLemma) })?.surface
        }
        // Pointed/unpointed variants are the same spelling analysis. Prefer the
        // explicitly vowelized source form without conflating different analyses.
        let groups=Dictionary(grouping:candidates,by:{ SemiticUnicode.key($0.surface) })
        guard groups.count == 1 else { return nil }
        return candidates.sorted { $0.surface.unicodeScalars.count == $1.surface.unicodeScalars.count ? $0.id < $1.id : $0.surface.unicodeScalars.count > $1.surface.unicodeScalars.count }.first?.surface
    }
}
