import Foundation

/// Chooses documented senses and actual alternatives from the local dictionary.
/// No target word is returned unless it occurs in that sense's licensed data.
enum GrammaticalSenseResolver {
    static func permitsIsolated(_ entry: LexicalEntry, token: EnglishToken, language: String) -> Bool {
        let target = key(entry.targetLemma)
        if language == "de", token.lemma == "for", ["lang","tagelang","-lang"].contains(target) { return false }
        if language == "ru", token.lemma == "if", target == "ли" { return false }
        if language == "ru", token.lemma == "until", target.contains("не") { return false }
        if language == "ru", token.lemma == "unless" { return false }
        return true
    }
    static func resolve(_ entries: [LexicalEntry], token: EnglishToken, language: String) -> SenseResolver.Resolution? {
        guard ["de","ru"].contains(language) else { return SenseResolver.resolve(entries:entries,token:token) }
        let context = Set((token.nearbyWords ?? []).map { $0.lowercased() })
        let following = token.followingNoun ?? token.followingWord ?? ""
        let temporal = Set(["morning","evening","night","day","week","month","year","hour","minute","second","lunch","dinner","breakfast","meal","meeting","class","lesson","work","school","holiday","sunrise","sunset","noon","midnight"])
        let spatial = Set(["room","house","office","city","village","forest","garden","park","box","bag","cup","car","table","floor","wall","door","window","bench","ground","desk","shelf","road","river","tree","oak","train","station","railing","building","bridge","hill","mountain","school","church","shop","store","street","coast","kitchen"])
        func select(_ definitions: [String], _ preferred: [String] = []) -> SenseResolver.Resolution? {
            let candidates = entries.filter { $0.partOfSpeech == token.pos && definitions.contains($0.morphologicalTags["definition"] ?? "") }
            for preferredWord in preferred {
                for entry in candidates {
                    if let match = alternatives(entry).first(where: { key($0) == key(preferredWord) }) {
                        return .init(entry: replacingTarget(entry, match), confidence: 0.94)
                    }
                }
            }
            guard let entry = candidates.first else { return nil }
            let targets = Set(candidates.map { key($0.targetLemma) })
            guard candidates.count == 1 || targets.count == 1 else { return nil }
            return .init(entry: entry, confidence: 0.9)
        }
        switch token.pos {
        case "conjunction":
            switch token.lemma {
            case "when":
                return select(["as soon as, at the time that","during the time that",""], language == "de" ? [past(token) ? "als" : "wenn"] : ["когда"])
            case "while":
                let contrast = [Set(["poor","rich"]),Set(["small","large"]),Set(["old","young"]),Set(["busy","free"])].contains { $0.isSubset(of: context) }
                return select([contrast ? "although" : "during the same time that"], language == "de" ? [contrast ? "während" : "während"] : [contrast ? "хотя" : "пока"])
            case "since":
                let clausePast = token.followingTokens.first { $0.1 == "verb" }?.2 == "VBD"
                if clausePast, !context.isDisjoint(with:["have","has","had"]) {
                    return select(["from the time that"],language == "de" ? ["seitdem","seit"] : ["с тех пор как"])
                }
                return nil
            case "until": return select(["up to the time that"], language == "de" ? ["bis"] : ["пока не"])
            case "unless": return select(["except on a specified condition"])
            case "for": return select(["because"], language == "de" ? ["denn"] : ["ибо"])
            case "if":
                let precedingVerb = token.precedingTokens.reversed().first { $0.1 == "verb" }?.0 ?? ""
                let indirect = ["ask","asked","asks","wonder","wondered","know","knew"].contains(precedingVerb)
                if indirect { return language == "de" ? select(["whether"],["ob"]) : nil }
                return select(["supposing that"], language == "de" ? ["wenn"] : ["если"])
            case "as":
                return nil // Temporal, causal and comparison readings must not be conflated.
            default: return SenseResolver.resolve(entries: entries, token: token)
            }
        case "preposition":
            switch token.lemma {
            case "after": return select(["subsequently; following in time; later than"], language == "de" ? ["nach"] : ["после"])
            case "before":
                return select([spatial.contains(following) ? "in front of in space" : "earlier than"], language == "de" ? ["vor"] : [spatial.contains(following) ? "перед" : "до"])
            case "during": return select(["for all of a given time interval","within a given time interval"], language == "de" ? ["während"] : ["в течение"])
            case "since": return select(["from (time)"], language == "de" ? ["seit"] : ["с"])
            case "until": return select(["up to the time of"], language == "de" ? ["bis zu"] : ["до"])
            case "from":
                let container = spatial.contains(following)
                return select(["with the source or provenance of or at","with the origin, starting point or initial reference of or at"], language == "de" ? [container ? "aus" : "von"] : [container ? "из" : "от"])
            case "to":
                return select(["in the direction of, and arriving at"], language == "de" ? ["zu"] : [spatial.contains(following) ? "в" : "к"])
            case "at":
                return select([temporal.contains(following) ? "indicating time" : "in or very near a particular place"], language == "de" ? [temporal.contains(following) ? "um" : "bei"] : ["в"])
            case "for":
                if temporal.contains(following) {
                    let ongoing = !context.isDisjoint(with: ["has","have","had"])
                    return select(["over (a period of time)"], language == "de" ? [ongoing ? "seit" : "lang"] : ["в течение"])
                }
                return select(["in order to obtain or acquire","supporting",""], language == "de" ? ["für"] : ["для"])
            case "under": return select(["at a lower level than","beneath the surface of"], language == "de" ? ["unter"] : ["под"])
            case "behind" where spatial.contains(following):
                return select(["at the back of"], language == "de" ? ["hinter"] : ["за","позади"])
            case "around" where spatial.contains(following):
                return select(["forming a circle or closed curve containing","following a path which curves near"],language == "de" ? ["um","herum"] : ["вокруг"])
            case "toward", "towards":
                return select(["in the direction of"],language == "de" ? ["zu","in Richtung"] : ["к"])
            case "over":
                return select(["physical positioning: on top of; above","physical positioning: across or spanning"], language == "de" ? ["über"] : ["над"])
            case "about": return select(["concerning","concerned with, engaged in"], language == "de" ? ["über"] : ["о"])
            case "of":
                let material = ["made","built","consists","composed"].contains(token.previousWord ?? "")
                return select([material ? "containing, comprising or made from" : "possessive genitive: belonging to"], language == "de" ? [material ? "aus" : "von"] : [material ? "из" : "-ов"])
            case "as": return select(["In the role of"], language == "de" ? ["als"] : ["в качестве"])
            case "in":
                if temporal.contains(following) { return select(["during a period of time"], language == "de" ? ["in"] : ["в течение"]) }
                if spatial.contains(following) { return select(["contained by"], language == "de" ? ["in"] : ["в"]) }
                return SenseResolver.resolve(entries:entries,token:token)
            case "on":
                if temporal.contains(following) { return select(["at the date of"], language == "de" ? ["an"] : ["в"]) }
                return SenseResolver.resolve(entries: entries, token: token)
            default:
                if let result = SenseResolver.resolve(entries: entries, token: token) { return result }
                // A truly monosemous, invariant preposition needs no whitelist membership.
                let allowed = entries.filter { $0.partOfSpeech == "preposition" && !$0.targetLemma.hasPrefix("-") && !$0.targetLemma.contains("...") }
                if Set(allowed.map { key($0.targetLemma) }).count == 1, let first = allowed.first { return .init(entry:first,confidence:0.88) }
                return nil
            }
        case "verb":
            switch token.lemma {
            case "be":
                if token.followingPOS == "adjective" { return select(["used to indicate that the subject has the qualities described by an adjective"]) }
                if ["preposition","adverb"].contains(token.followingPOS ?? "") { return select(["to occupy a place"], language == "de" ? ["sein"] : ["находиться"]) }
                return select(["used to declare the subject and object identical or equivalent"], language == "de" ? ["sein"] : ["быть"])
            case "have": return select(["to possess"], language == "de" ? ["haben"] : ["иметь"])
            case "can": return select(["to be able to; to know how to"], language == "de" ? ["können"] : ["мочь"])
            case "must": return select(["be required to"])
            case "may": return select(["have permission to"], language == "de" ? ["dürfen"] : ["мочь"])
            case "do": return select(["perform, execute","perform tasks"], language == "de" ? ["machen"] : ["делать"])
            case "will": return select(["indicating future action"])
            case "should": return select(["expressing obligation"], language == "de" ? ["sollen"] : ["должен"])
            case "work": return select(["intransitive: to do a specific task"], language == "de" ? ["arbeiten"] : ["работать"])
            case "laugh": return select(["show mirth by peculiar movement of the muscles of the face and emission of sounds"], language == "de" ? ["lachen"] : ["смеяться"])
            case "run": return SenseResolver.resolve(entries: entries, token: token)
            default:
                if let resolved = SenseResolver.resolve(entries: entries, token: token) { return resolved }
                // An unqualified dictionary sense is a real lexical sense, not an invented pair.
                return select([""])
            }
        default: return SenseResolver.resolve(entries: entries, token: token)
        }
    }
    static func alternatives(_ entry: LexicalEntry) -> [String] {
        let raw = entry.morphologicalTags["alternatives"] ?? "[]"
        let values = (try? JSONDecoder().decode([String].self, from: Data(raw.utf8))) ?? []
        var seen: Set<String> = []
        return ([entry.targetLemma] + values).filter { seen.insert(key($0)).inserted }
    }
    static func replacingTarget(_ entry: LexicalEntry, _ target: String) -> LexicalEntry {
        .init(englishLemma: entry.englishLemma, targetLemma: target, senseID: entry.senseID, partOfSpeech: entry.partOfSpeech,
              contextExamples: entry.contextExamples, morphologicalTags: entry.morphologicalTags, provenance: entry.provenance)
    }
    private static func key(_ word: String) -> String { word.replacingOccurrences(of: "\u{301}", with: "").precomposedStringWithCanonicalMapping.lowercased() }
    private static func past(_ token: EnglishToken) -> Bool {
        token.followingTokens.first { $0.1 == "verb" }?.2 == "VBD"
    }
}
