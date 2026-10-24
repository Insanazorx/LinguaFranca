import Foundation

/// Russian ли follows the predicate; inserting it at the English "if" position is wrong.
enum IndirectQuestionPractice {
    static func ranges(_ tokens: [EnglishToken]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        for i in tokens.indices where tokens[i].surface.lowercased() == "if" && i+2 < tokens.count {
            guard ["ask","asks","asked","wonder","wonders","wondered","know","knows","knew"].contains(tokens[i].precedingTokens.reversed().first { $0.1 == "verb" }?.0 ?? ""),
                  tokens[i+1].pos == "pronoun", tokens[i+2].pos == "verb", tokens[i+2].sentenceIndex == tokens[i].sentenceIndex,
                  !["noun","determiner","propernoun"].contains(tokens[i+2].followingPOS ?? "") else { continue }
            result.append(i..<(i+3))
        }
        return result
    }
    static func entry(_ range: Range<Int>,tokens:[EnglishToken],pack:any LanguagePack,text:String) async throws -> LexicalEntry? {
        let marker = tokens[range.lowerBound], subject = tokens[range.lowerBound+1], verb = tokens[range.lowerBound+2]
        let code = pack.metadata.languageCode
        let markers = try await pack.lookup(englishLemma:"if")
        let desired = code == "de" ? "ob" : code == "ru" ? "ли" : ""
        guard let connective = markers.first(where: { $0.morphologicalTags["definition"] == "whether" && GrammaticalSenseResolver.alternatives($0).contains(desired) }) else { return nil }
        let pronouns = try await pack.lookup(englishLemma:subject.lemma)
        let preferred: [String:String] = code == "de" ? ["i":"ich","you":"du","he":"er","she":"sie","we":"wir","they":"sie","it":"es"] : ["i":"я","you":"ты","he":"он","she":"она","we":"мы","they":"они","it":"оно"]
        guard let pronoun = preferred[subject.lemma], pronouns.contains(where: { GrammaticalSenseResolver.alternatives($0).map { $0.replacingOccurrences(of:"\u{301}",with:"") }.contains(pronoun) }),
              let features = EnglishInflection.features(verb,aggressive:true) else { return nil }
        for lemma in EnglishInflection.lemmas(verb) {
            var source = verb; source.lemma = lemma
            guard let sense = GrammaticalSenseResolver.resolve(try await pack.lookup(englishLemma:lemma),token:source,language:code) else { continue }
            for alternative in GrammaticalSenseResolver.alternatives(sense.entry) {
                let entry = GrammaticalSenseResolver.replacingTarget(sense.entry,alternative)
                guard let finite = try await pack.inflect(entry,features:features) else { continue }
                let output = code == "de" ? desired + " " + pronoun + " " + finite : finite + " " + desired + " " + pronoun
                let start = marker.span.location, end = verb.span.location+verb.span.length
                return .init(englishLemma:(text as NSString).substring(with:.init(location:start,length:end-start)).lowercased(),targetLemma:output,
                    senseID:"indirect:"+connective.senseID+":"+entry.senseID,partOfSpeech:"clause",contextExamples:[],
                    morphologicalTags:["definition":"indirect yes/no question · \(desired)"],provenance:entry.provenance)
            }
        }
        return nil
    }
}
