import Foundation

enum VerbPhrasePractice {
    struct Pattern {
        let indices: Range<Int>
        let negative: Bool
        let kind: String
    }
    static func patterns(_ tokens: [EnglishToken]) -> [Pattern] {
        var result: [Pattern] = []
        for i in tokens.indices where tokens[i].pos == "verb" && i+1 < tokens.count {
            let word = tokens[i].surface.lowercased()
            var end = i+1
            let negative = tokens[end].surface.lowercased() == "not"
            if negative { end += 1 }
            guard end < tokens.count, tokens[end].sentenceIndex == tokens[i].sentenceIndex else { continue }
            if ["am","is","are","was","were"].contains(word), tokens[end].pennTag == "VBG" {
                result.append(.init(indices:i..<(end+1),negative:negative,kind:"progressive"))
            } else if ["do","does","did"].contains(word), tokens[end].pennTag == "VB" {
                result.append(.init(indices:i..<(end+1),negative:negative,kind:"do-support"))
            } else if ["am","is","are"].contains(word), tokens[end].pos == "adjective", !negative {
                result.append(.init(indices:i..<(end+1),negative:false,kind:"copula-adjective"))
            }
        }
        return result
    }
    static func entry(_ pattern: Pattern, tokens: [EnglishToken], pack: any LanguagePack, text: String) async throws -> LexicalEntry? {
        let head = tokens[pattern.indices.lowerBound], object = tokens[pattern.indices.upperBound-1]
        let code = pack.metadata.languageCode
        if pattern.kind == "copula-adjective", code != "ru" { return nil }
        var features = EnglishInflection.subjectFeatures(head,allowSecondPerson:true)
        if features["person"] == nil, ["is","was","does"].contains(head.surface.lowercased()) { features["person"] = "3"; features["number"] = "singular" }
        guard features["person"] != nil else { return nil }
        features["form"] = pattern.kind == "copula-adjective" ? "predicative" : "finite"
        features["tense"] = ["was","were","did"].contains(head.surface.lowercased()) ? "past" : "present"
        features["allowGeneralPast"] = "true"
        var resolved: [SenseResolver.Resolution] = []
        for lemma in EnglishInflection.lemmas(object) {
            var token = object; token.lemma = lemma
            if let match = GrammaticalSenseResolver.resolve(try await pack.lookup(englishLemma:lemma),token:token,language:code) { resolved.append(match) }
        }
        guard resolved.count == 1, let resolution = resolved.first else { return nil }
        // Adjective tables have no tense dimension.
        if object.pos == "adjective" { features.removeValue(forKey:"tense") }
        for alternative in GrammaticalSenseResolver.alternatives(resolution.entry) {
            let entry = GrammaticalSenseResolver.replacingTarget(resolution.entry,alternative)
            guard let finite = try await pack.inflect(entry,features:features) else { continue }
            var output = finite
            if pattern.negative {
                output = code == "de" ? finite + " nicht" : code == "ru" ? "не " + finite : ""
            }
            guard try await pack.validateReplacement(entry,surface:output,context:head.sentence) else { continue }
            let start = head.span.location, end = object.span.location + object.span.length
            let source = (text as NSString).substring(with:NSRange(location:start,length:end-start))
            return .init(englishLemma: source.lowercased(),targetLemma:output,senseID:"predicate:"+entry.senseID,
                partOfSpeech:"verbPhrase",contextExamples:[],morphologicalTags:["definition":"\(pattern.kind) · \(features["tense"] ?? "present")"],provenance:entry.provenance)
        }
        return nil
    }
}
