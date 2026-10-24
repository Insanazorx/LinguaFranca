// Native inference for the MIT-licensed averaged perceptron model.
// Algorithm: Matthew Honnibal (2013), NLTK port by Long Duong / NLTK Project (2015).
// Attribution and full MIT terms are bundled with the model.
import Foundation

struct BundledEnglishTagger: Sendable {
    private let weights: [String:[String:Double]]
    private let dictionary: [String:String]
    private let classes: [String]

    init(directory: URL) throws {
        func data(_ name: String) throws -> Data {
            try Data(contentsOf: directory.appendingPathComponent("averaged_perceptron_tagger_eng.\(name).json"))
        }
        let decoder = JSONDecoder()
        weights = try decoder.decode([String:[String:Double]].self,from:data("weights"))
        dictionary = try decoder.decode([String:String].self,from:data("tagdict"))
        classes = try decoder.decode([String].self,from:data("classes")).sorted()
        guard !weights.isEmpty, !classes.isEmpty else { throw DomainError.invalidInput("The offline English tagger is empty.") }
    }

    func tags(for words: [String]) -> [String] {
        let context = ["-START-","-START2-"] + words.map(Self.normalize) + ["-END-","-END2-"]
        var previous = "-START-", previous2 = "-START2-", result: [String] = []
        for (index, word) in words.enumerated() {
            let tag: String
            if let known = dictionary[word] { tag = known }
            else {
                let i = index + 2
                let features = ["bias", "i suffix \(word.suffix(3))", "i pref1 \(word.prefix(1))",
                    "i-1 tag \(previous)", "i-2 tag \(previous2)", "i tag+i-2 tag \(previous) \(previous2)",
                    "i word \(context[i])", "i-1 tag+i word \(previous) \(context[i])",
                    "i-1 word \(context[i-1])", "i-1 suffix \(context[i-1].suffix(3))", "i-2 word \(context[i-2])",
                    "i+1 word \(context[i+1])", "i+1 suffix \(context[i+1].suffix(3))", "i+2 word \(context[i+2])"]
                var scores: [String:Double] = [:]
                for feature in features {
                    for (label, weight) in weights[feature] ?? [:] { scores[label, default:0] += weight }
                }
                tag = classes.max {
                    let a = scores[$0, default:0], b = scores[$1, default:0]
                    return a == b ? $0 < $1 : a < b
                } ?? "NN"
            }
            result.append(tag); previous2 = previous; previous = tag
        }
        return result
    }

    private static func normalize(_ word: String) -> String {
        if word.contains("-"), !word.hasPrefix("-") { return "!HYPHEN" }
        if word.count == 4, word.allSatisfy(\.isNumber) { return "!YEAR" }
        if word.first?.isNumber == true { return "!DIGITS" }
        return word.lowercased()
    }

    static func partOfSpeech(_ tag: String, word: String) -> String {
        if ["NNP","NNPS"].contains(tag) { return "propernoun" }
        if tag.hasPrefix("NN") { return "noun" }
        if tag.hasPrefix("VB") || tag == "MD" { return "verb" }
        if tag.hasPrefix("JJ") { return "adjective" }
        if tag.hasPrefix("RB") || tag == "WRB" { return "adverb" }
        if tag == "RP" { return "particle" }
        if tag == "PRP" { return "pronoun" }
        if ["DT","PDT","PRP$","WDT"].contains(tag) { return "determiner" }
        if tag == "CC" { return "conjunction" }
        if tag == "IN" {
            return ["because","although","whereas","unless","if","while","though","that"].contains(word.lowercased()) ? "conjunction" : "preposition"
        }
        if tag == "TO" { return "preposition" }
        return "unknown"
    }
}
