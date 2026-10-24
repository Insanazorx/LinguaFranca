import Foundation
import NaturalLanguage

struct EnglishToken: Sendable {
    let surface: String
    var lemma: String
    var pos: String
    let span: UTF16Span
    let sentence: String
    let sentenceIndex: Int
    var nearbyWords: [String]? = nil
    var previousWord: String? = nil
    var followingWord: String? = nil
    var followingPOS: String? = nil
    var followingTokens: [(String,String,String?)] = []
    var isCompoundComponent = false
    var isSentenceInitial = false
    var isPlural = false
    var followingNoun: String? = nil
    var pennTag: String? = nil
    var precedingTokens: [(String, String, Bool)] = []
}

enum EnglishAnalyzer {
    static func tokens(in text: String, bundledTagger: BundledEnglishTagger? = nil) -> [EnglishToken] {
        let sentenceTokenizer = NLTokenizer(unit: .sentence)
        sentenceTokenizer.string = text
        sentenceTokenizer.setLanguage(.english)
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = text
        tagger.setLanguage(.english, range: text.startIndex..<text.endIndex)
        var result: [EnglishToken] = [], sentenceIndex = 0
        sentenceTokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { sentenceRange, _ in
            let sentence = String(text[sentenceRange])
            var units: [(Range<String.Index>, String?, String?)] = []
            tagger.enumerateTags(in: sentenceRange, unit: .word, scheme: .lexicalClass,
                                 options: [.omitWhitespace]) { tag, range in
                units.append((range,tag?.rawValue.lowercased(),
                    bundledTagger == nil ? tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue.lowercased() : nil))
                return true
            }
            let bundledTags = bundledTagger?.tags(for:units.map { String(text[$0.0]) })
            for (i, unit) in units.enumerated() {
                let (range, applePOS, appleLemma) = unit
                let surface = String(text[range])
                guard surface.unicodeScalars.contains(where: CharacterSet.letters.contains) else { continue }
                let raw = bundledTags.map { BundledEnglishTagger.partOfSpeech($0[i],word:surface) } ?? applePOS ?? "unknown"
                let pos = raw
                let lemma = appleLemma ?? surface.lowercased()
                let ns = NSRange(range, in: text)
                var token = EnglishToken(surface: surface, lemma: lemma, pos: pos,
                    span: UTF16Span(location: ns.location, length: ns.length), sentence: sentence, sentenceIndex: sentenceIndex)
                token.isPlural = bundledTags?[i] == "NNS" || (pos == "noun" && lemma != surface.lowercased())
                token.pennTag = bundledTags?[i]
                result.append(token)
            }
            sentenceIndex += 1
            return true
        }
        for i in result.indices {
            if result[i].surface.lowercased() == "to", i+1 < result.count, result[i+1].pennTag == "VB" {
                result[i].pos = "infinitiveMarker"
            }
            if result[i].surface.lowercased() == "that", result[i].pos == "conjunction", i > 0,
               ["noun","propernoun"].contains(result[i-1].pos), !["fact","idea","hope","belief","news","claim"].contains(result[i-1].lemma) {
                result[i].pos = "pronoun"
            }
            if ["before","after","since","when","as","for"].contains(result[i].surface.lowercased()) {
                let following = result.dropFirst(i+1).prefix(4).filter { $0.sentenceIndex == result[i].sentenceIndex }
                var clause = Array(following)
                if clause.first?.pos == "determiner" { clause.removeFirst() }
                let subject = clause.first
                if !clause.isEmpty { clause.removeFirst() }
                while clause.first?.pos == "adverb" { clause.removeFirst() }
                if subject.map({ ["pronoun","noun","propernoun"].contains($0.pos) }) == true,
                   clause.first?.pos == "verb" {
                    result[i].pos = "conjunction"
                }
            }
            result[i].followingTokens = result.dropFirst(i+1).prefix(8).filter { $0.sentenceIndex == result[i].sentenceIndex }.map { ($0.surface.lowercased(),$0.pos,$0.pennTag) }
            result[i].isSentenceInitial = i == 0 || result[i-1].sentenceIndex != result[i].sentenceIndex
            result[i].precedingTokens = result[..<i].suffix(6).filter { $0.sentenceIndex == result[i].sentenceIndex }
                .map { ($0.surface.lowercased(), $0.pos, $0.isPlural) }
            let sentenceTokens = result.indices.filter { result[$0].sentenceIndex == result[i].sentenceIndex }
            let repeated = sentenceTokens.filter { result[$0].lemma == result[i].lemma }.count > 1
            let neighbours = repeated ? Array(max(0, i-5)...min(result.count-1, i+5)) : sentenceTokens
            result[i].nearbyWords = neighbours.filter { result[$0].sentenceIndex == result[i].sentenceIndex && $0 != i }
                .map { result[$0].lemma }
            if i > 0, result[i-1].sentenceIndex == result[i].sentenceIndex { result[i].previousWord = result[i-1].surface.lowercased() }
            if i+1 < result.count, result[i+1].sentenceIndex == result[i].sentenceIndex {
                result[i].followingWord = result[i+1].surface.lowercased()
                result[i].followingPOS = result[i+1].pos
                for j in (i+1)...min(result.count-1,i+6) where result[j].sentenceIndex == result[i].sentenceIndex {
                    if result[j].pos == "noun" { result[i].followingNoun = EnglishAnalyzer.nounLemmaCandidates(result[j]).first ?? result[j].lemma; break }
                    if !["adjective","determiner"].contains(result[j].pos) && result[j].pennTag != "CD" { break }
                }
            }
            // Never translate just one side of a compound, including hyphenated proper names.
            if let range = try? result[i].span.range(in: text) {
                let hyphens: Set<Character> = ["-", "‐", "‑", "–"]
                let before = range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : nil
                let after = range.upperBound < text.endIndex ? text[range.upperBound] : nil
                result[i].isCompoundComponent = before.map(hyphens.contains) == true || after.map(hyphens.contains) == true
            }
        }
        return result
    }

    static func nounLemmaCandidates(_ token: EnglishToken) -> [String] {
        guard token.isPlural else { return [token.lemma] }
        if token.lemma != token.surface.lowercased() { return [token.lemma] }
        let word = token.surface.lowercased()
        // English inflection exceptions, not translation pairs. Every candidate still needs
        // a dictionary sense and an independently attested target plural before replacement.
        let irregular = ["children":"child", "men":"man", "women":"woman", "people":"person",
            "teeth":"tooth", "feet":"foot", "mice":"mouse", "geese":"goose", "leaves":"leaf",
            "lives":"life", "knives":"knife", "wolves":"wolf", "shelves":"shelf", "halves":"half"]
        if let base = irregular[word] { return [base] }
        if word.hasSuffix("ies"), word.count > 3 { return [String(word.dropLast(3)) + "y"] }
        var bases: [String] = []
        if ["ses","xes","zes","ches","shes"].contains(where:word.hasSuffix) { bases.append(String(word.dropLast(2))) }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), word.count > 2 { bases.append(String(word.dropLast())) }
        return Array(Set(bases)).sorted()
    }
}
