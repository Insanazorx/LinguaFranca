import Foundation

enum EnglishInflection {
    static func lemmas(_ token: EnglishToken) -> [String] {
        if token.pos == "noun" { return EnglishAnalyzer.nounLemmaCandidates(token) }
        let word = token.surface.lowercased()
        if token.pos == "adjective", token.pennTag == "JJR" {
            if word == "better" { return ["good"] }; if word == "worse" { return ["bad"] }
            if word.hasSuffix("ier") { return [String(word.dropLast(3)) + "y"] }
            return word.hasSuffix("er") ? [String(word.dropLast(2)), String(word.dropLast())] : [token.lemma]
        }
        guard token.pos == "verb" else { return [token.lemma] }
        let irregular = ["am":"be","is":"be","are":"be","was":"be","were":"be","been":"be","being":"be","has":"have","had":"have","does":"do","did":"do","done":"do","could":"can","went":"go","gone":"go","wrote":"write","written":"write","saw":"see","seen":"see",
            "took":"take","taken":"take","gave":"give","given":"give","made":"make","found":"find",
            "thought":"think","knew":"know","known":"know","came":"come","became":"become","left":"leave",
            "spoke":"speak","spoken":"speak","ate":"eat","eaten":"eat","drank":"drink","drunk":"drink",
            "bought":"buy","brought":"bring","taught":"teach","caught":"catch","felt":"feel","kept":"keep",
            "slept":"sleep","stood":"stand","understood":"understand","ran":"run","began":"begin","begun":"begin",
            "broke":"break","broken":"break","chose":"choose","chosen":"choose","drove":"drive","driven":"drive",
            "grew":"grow","grown":"grow","held":"hold","heard":"hear","lost":"lose","met":"meet","paid":"pay",
            "read":"read","said":"say","sent":"send","sat":"sit","spent":"spend","won":"win","wore":"wear","worn":"wear"]
        if let base = irregular[word] { return [base] }
        var result = [token.lemma]
        if token.pennTag == "VBZ" {
            if word.hasSuffix("ies") { result.append(String(word.dropLast(3)) + "y") }
            if word.hasSuffix("es") { result.append(String(word.dropLast(2))) }
            if word.hasSuffix("s") { result.append(String(word.dropLast())) }
        }
        if ["VBD","VBN"].contains(token.pennTag ?? ""), word.hasSuffix("ed") {
            if word.hasSuffix("ied") { result.append(String(word.dropLast(3)) + "y") }
            result += bases(String(word.dropLast(2))) + [String(word.dropLast())]
        }
        if token.pennTag == "VBG", word.hasSuffix("ing") { result += bases(String(word.dropLast(3))) }
        return Array(Set(result)).sorted()
    }
    private static func bases(_ stem: String) -> [String] {
        var values = [stem, stem + "e"]
        let chars = Array(stem)
        if chars.count > 2, chars[chars.count-1] == chars[chars.count-2] { values.append(String(stem.dropLast())) }
        if stem.hasSuffix("y") { values.append(String(stem.dropLast()) + "ie") }
        return values
    }
    static func features(_ token: EnglishToken) -> [String:String]? { features(token,aggressive:false) }
    static func features(_ token: EnglishToken, aggressive: Bool) -> [String: String]? {
        if !["verb","adjective"].contains(token.pos) { return ["number": token.isPlural ? "plural" : "singular"] }
        let subject = subjectFeatures(token, allowSecondPerson:aggressive)
        if token.pos == "adjective" {
            guard token.precedingTokens.suffix(2).contains(where: { ["is","am","are","was","were","be","been"].contains($0.0) }),
                  !["noun","adjective"].contains(token.followingPOS ?? ""),
                  token.pennTag != "JJS" else { return nil }
            return subject.merging(["form": token.pennTag == "JJR" ? "comparative" : "predicative"]) { _, new in new }
        }
        let auxiliary = Set(["be","am","is","are","was","were","been","being","have","has","had","do","does","did","can","could","may","might","must","shall","should","will","would"])
        guard aggressive || !auxiliary.contains(token.surface.lowercased()) else { return nil }
        if aggressive, token.pennTag == "MD" {
            guard subject["person"] != nil else { return nil }
            var result = subject; result["form"] = "finite"; result["tense"] = token.surface.lowercased() == "could" ? "past" : "present"
            result["allowGeneralPast"] = "true"
            return result
        }
        switch token.pennTag {
        case "VB":
            if token.previousWord == "to" || ["can","could","may","might","must","shall","should","will","would"].contains(token.previousWord ?? "") { return ["form":"infinitive"] }
            guard aggressive, subject["person"] != nil else { return nil }
            return subject.merging(["form":"finite","tense":"present"]) { _, new in new }
        case "VBZ": return ["form":"finite","tense":"present","person":"3","number":"singular"]
        case "VBP", "VBD":
            guard subject["person"] != nil, subject["number"] != nil else { return nil }
            var result = subject; result["form"] = "finite"; result["tense"] = token.pennTag == "VBD" ? "past" : "present"
            let words = Set(token.sentence.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
            if aggressive { result["allowGeneralPast"] = "true" }
            if !words.isDisjoint(with: ["every","each","often","usually","always"]) { result["habitual"] = "true" }
            return result
        case "VBG":
            guard token.isSentenceInitial, token.sentence.contains(",") else { return nil }
            return ["form":"converb"]
        case "VBN":
            guard ["have","has","had"].contains(token.previousWord ?? "") else { return nil }
            return ["form":"pastParticiple"]
        default: return nil
        }
    }
    static func subjectFeatures(_ token: EnglishToken, allowSecondPerson: Bool = false) -> [String: String] {
        for (word, pos, plural) in token.precedingTokens.reversed() {
            if word == "you", !allowSecondPerson { return [:] }
            if let value: [String: String] = [
                "you":["person":"2","number":"singular"], "i":["person":"1","number":"singular"], "we":["person":"1","number":"plural"],
                "they":["person":"3","number":"plural"], "he":["person":"3","number":"singular","gender":"masculine"],
                "she":["person":"3","number":"singular","gender":"feminine"], "it":["person":"3","number":"singular","gender":"neuter"]
            ][word] { return value }
            if pos == "noun" || pos == "propernoun" { return ["person":"3","number": plural ? "plural" : "singular"] }
            if ["and","or","but"].contains(word) { continue }
            if ["preposition","conjunction","pronoun"].contains(pos) { break }
        }
        return [:]
    }
}
