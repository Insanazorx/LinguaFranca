import Foundation

/// Recognizes bounded complements; the pack supplies independently attested forms.
/// Unsupported phrases are reserved too, so their preposition cannot be inserted alone.
enum PrepositionalPractice {
    struct Pattern {
        let indices: Range<Int>
        let article: String?
        let supported: Bool
    }
    static func patterns(_ tokens: [EnglishToken]) -> [Pattern] {
        var result: [Pattern] = [], cursor = 0
        while cursor < tokens.count {
            let start = cursor, head = tokens[start]
            cursor += 1
            guard head.pos == "preposition", start + 1 < tokens.count,
                  tokens[start+1].sentenceIndex == head.sentenceIndex else { continue }
            var end = start + 1, article: String?
            if tokens[end].pos == "determiner" {
                article = tokens[end].surface.lowercased(); end += 1
            }
            var modified = false
            while end < tokens.count, tokens[end].sentenceIndex == head.sentenceIndex,
                  ["adjective","adverb"].contains(tokens[end].pos), end - start < 6 {
                modified = true; end += 1
            }
            guard end < tokens.count, tokens[end].sentenceIndex == head.sentenceIndex,
                  ["noun","pronoun","verb","propernoun"].contains(tokens[end].pos) else { continue }
            let object = tokens[end]
            let supported = !modified && (article == nil || ["the","a","an"].contains(article!))
                && (object.pos == "noun" || (object.pennTag == "VBG" && head.lemma == "without" && article == nil))
                && !object.isCompoundComponent
                && !(end+1 < tokens.count && tokens[end+1].sentenceIndex == head.sentenceIndex
                     && ["noun","propernoun"].contains(tokens[end+1].pos))
            result.append(Pattern(indices: start..<(end+1), article: article, supported: supported))
            cursor = end + 1
        }
        return result
    }
    static func entry(pattern: Pattern, tokens: [EnglishToken], pack: any LanguagePack, source: String, aggressive: Bool = false, selector: (any ContextualSenseSelecting)? = nil) async throws -> LexicalEntry? {
        guard pattern.supported, let last = pattern.indices.last else { return nil }
        for i in pattern.indices.dropLast() {
            let start = tokens[i].span.location + tokens[i].span.length
            let gap = (source as NSString).substring(with: NSRange(location: start, length: tokens[i+1].span.location-start))
            guard gap.allSatisfy(\.isWhitespace) else { return nil }
        }
        let prep = tokens[pattern.indices.lowerBound], object = tokens[last]
        let prepEntries = try await pack.lookup(englishLemma: prep.lemma)
        let resolution = aggressive ? GrammaticalSenseResolver.resolve(prepEntries,token:prep,language:pack.metadata.languageCode) : SenseResolver.resolve(entries:prepEntries,token:prep)
        guard let head = resolution?.entry else { return nil }
        var matches: [SenseResolver.Resolution] = []
        var available: [LexicalEntry] = []
        for lemma in EnglishInflection.lemmas(object) {
            var token = object; token.lemma = lemma
            let entries = try await pack.lookup(englishLemma:lemma)
            available += entries
            if let match = SenseResolver.resolve(entries:entries, token: token) { matches.append(match) }
        }
        let code = pack.metadata.languageCode
        var selectedComplement = matches.count == 1 ? matches.first?.entry : nil
        if selectedComplement == nil, aggressive, let selector {
            let genitive = prep.lemma == "of" && head.morphologicalTags["definition"] == "possessive genitive: belonging to"
            let grammaticalCase = genitive ? "genitive" : governedCase(prep,language:code,head:head.targetLemma)
            var candidates: [(LexicalEntry,String)] = [], seen: Set<String> = []
            let context = SenseResolver.words(object.sentence)
            let ranked = available.enumerated().sorted {
                let a = SenseResolver.words($0.element.morphologicalTags["definition"] ?? "").intersection(context).count
                let b = SenseResolver.words($1.element.morphologicalTags["definition"] ?? "").intersection(context).count
                return a == b ? $0.offset < $1.offset : a > b
            }.map(\.element)
            for entry in ranked where entry.partOfSpeech == object.pos && seen.insert(entry.senseID).inserted {
                let definition = entry.morphologicalTags["definition"] ?? ""
                guard !["archaic","obsolete","vulgar","rare","slang"].contains(where:definition.localizedCaseInsensitiveContains) else { continue }
                for alternative in GrammaticalSenseResolver.alternatives(entry) {
                    let variant = GrammaticalSenseResolver.replacingTarget(entry,alternative)
                    let form: String?
                    if let grammaticalCase, object.pos == "noun" {
                        form = try await pack.nounPhrase(variant,number:object.isPlural ? "plural" : "singular",grammaticalCase:grammaticalCase,article:pattern.article)
                    } else if object.pennTag == "VBG", prep.lemma == "without" {
                        form = try await pack.inflect(variant,features:["form":code == "de" ? "infinitive" : "converb"])
                    } else { form = nil }
                    if let form { candidates.append((variant,form)); break }
                }
                if candidates.count == 9 { break }
            }
            if !candidates.isEmpty {
                let range = try object.span.range(in:source)
                // Mark the exact original span, including repeated surfaces.
                let start = source.index(range.lowerBound,offsetBy:-240,limitedBy:source.startIndex) ?? source.startIndex
                let end = source.index(range.upperBound,offsetBy:240,limitedBy:source.endIndex) ?? source.endIndex
                let marked = String(source[start..<range.lowerBound])+"[["+object.surface+"]]"+String(source[range.upperBound..<end])
                if let index = try await selector.selectSense(.init(expression:object.surface,partOfSpeech:object.pos,sentence:marked,languageCode:code,
                    options:candidates.map { .init(definition:String(($0.0.morphologicalTags["definition"] ?? "").prefix(240)),target:$0.1) })), candidates.indices.contains(index) {
                    selectedComplement = candidates[index].0
                }
            }
        }
        guard let complement = selectedComplement else { return nil }
        var output: String, explanation: String
        let targetHead = head.targetLemma.replacingOccurrences(of: "\u{301}", with: "")
        if object.pennTag == "VBG", prep.lemma == "without" {
            // Only the shared-subject adjunct, never a finite subordinate clause.
            guard prep.precedingTokens.contains(where: { $0.1 == "verb" }) else { return nil }
            if code == "de", targetHead == "ohne",
               let verb = try await pack.inflect(complement, features: ["form":"infinitive"]) {
                output = "ohne zu " + verb; explanation = "without + verb · ohne + zu + infinitive"
            } else if code == "ru", targetHead == "без",
                      let verb = try await pack.inflect(complement, features: ["form":"converb"]) {
                output = "не " + verb; explanation = "without + verb · negative imperfective converb"
            } else { return nil }
        } else {
            let genitive = prep.lemma == "of" && head.morphologicalTags["definition"] == "possessive genitive: belonging to"
            guard let grammaticalCase = genitive ? "genitive" : governedCase(prep, language: code, head: targetHead),
                  let noun = try await pack.nounPhrase(complement, number: object.isPlural ? "plural" : "singular",
                    grammaticalCase: grammaticalCase, article: pattern.article) else { return nil }
            output = genitive ? noun : targetHead + " " + noun
            // Russian obligatory/euphonic preposition variants before consonant clusters.
            if code == "ru" {
                let lower = noun.lowercased()
                if targetHead == "в", ["вс","вт"].contains(where: lower.hasPrefix) { output = "во " + noun }
                if targetHead == "с", ["с","з","ш","ж","щ"].contains(where: lower.hasPrefix),
                   lower.dropFirst().first.map({ !"аеёиоуыэюя".contains($0) }) == true { output = "со " + noun }
            }
            explanation = "\(prep.surface) + object · \(targetHead) + \(grammaticalCase)"
        }
        let start = tokens[pattern.indices.lowerBound].span.location
        let end = tokens[last].span.location + tokens[last].span.length
        let original = (source as NSString).substring(with: NSRange(location: start, length: end-start))
        let genitiveHead = prep.lemma == "of" && head.morphologicalTags["definition"] == "possessive genitive: belonging to"
        let validHead: Bool
        if genitiveHead { validHead = true }
        else { validHead = try await pack.validateReplacement(head,surface:head.targetLemma,context:prep.sentence) }
        guard validHead,
              try await pack.validateReplacement(complement, surface: output, context: prep.sentence) else { return nil }
        return LexicalEntry(englishLemma: original.lowercased(), targetLemma: output,
            senseID: "phrase:" + head.senseID + ":" + complement.senseID, partOfSpeech: "prepositionalPhrase",
            contextExamples: [], morphologicalTags: ["definition":explanation], provenance: complement.provenance)
    }
    private static func governedCase(_ token: EnglishToken, language: String, head: String) -> String? {
        let cases: [String:[String:String]] = [
            "de":["mit":"dative","ohne":"accusative","durch":"accusative","vor":"dative","nach":"dative","aus":"dative","von":"dative","zu":"dative","bei":"dative","für":"accusative","während":"genitive","seit":"dative"],
            "ru":["с":"instrumental","без":"genitive","сквозь":"accusative","через":"accusative","перед":"instrumental","после":"genitive","из":"genitive","от":"genitive","к":"dative","до":"genitive","для":"genitive","в течение":"genitive"]
        ]
        if let value = cases[language]?[head] { return value }
        if token.lemma == "into", ["in","в"].contains(head) { return "accusative" }
        if ["in","on"].contains(token.lemma), ["in","auf","в","на"].contains(head) {
            let stative = Set(["am","is","are","was","were","sit","sits","sat","stand","stands","stood","stay","stays","stayed","remain","remains","rest","rests","live","lives"])
            guard token.precedingTokens.contains(where: { stative.contains($0.0) }) else { return nil }
            return language == "de" ? "dative" : language == "ru" ? "prepositional" : nil
        }
        return nil
    }
}
