import Foundation

struct LexicalExpressionChoice: Sendable {
    let range: Range<Int>
    let entry: LexicalEntry
    let surface: String
    let pack: any LanguagePack
}
struct LexicalExpressionResult: Sendable {
    let choices: [LexicalExpressionChoice]
    let protectedRanges: [Range<Int>]
}

/// Longest-first lookup of actual multiword entries: because of, as soon as, look for…
enum LexicalExpressionPractice {
    static func choices(tokens:[EnglishToken],text:String,required:Set<Int>,packs:[any LanguagePack],selector:(any ContextualSenseSelecting)?,excluded:Set<Int> = []) async throws -> LexicalExpressionResult {
        var result: [LexicalExpressionChoice] = [], cursor = 0
        var protected: [Range<Int>] = []
        while cursor < tokens.count {
            try Task.checkCancellation()
            let start = cursor
            var selected: [LexicalExpressionChoice] = []
            var recognizedRange: Range<Int>?
            if tokens.count-start >= 2 {
                for size in stride(from:min(4,tokens.count-start),through:2,by:-1) {
                    let range = start..<(start+size)
                    guard excluded.isDisjoint(with:range), !required.isDisjoint(with:range), tokens[range.upperBound-1].sentenceIndex == tokens[start].sentenceIndex else { continue }
                    var adjacent = true
                    for i in range.dropLast() {
                        let gapStart = tokens[i].span.location + tokens[i].span.length
                        let gap = (text as NSString).substring(with:.init(location:gapStart,length:tokens[i+1].span.location-gapStart))
                        if !gap.allSatisfy(\.isWhitespace) { adjacent = false; break }
                    }
                    guard adjacent else { continue }
                    let words = range.map { tokens[$0].surface.lowercased() }
                    var phrases = [words.joined(separator:" ")]
                    if tokens[start].pos == "verb" {
                        phrases += EnglishInflection.lemmas(tokens[start]).map { ([$0]+words.dropFirst()).joined(separator:" ") }
                    }
                    for pack in packs {
                        var candidates: [(LexicalEntry,String?)] = [], seen: Set<String> = []
                        for phrase in Set(phrases).sorted() {
                            let entries = try await pack.lookup(englishLemma:phrase)
                            if entries.contains(where: { ["conjunction","preposition","prepositional_phrase"].contains($0.partOfSpeech) }) { recognizedRange = range }
                            for entry in entries where ["verb","conjunction","preposition","prepositional_phrase"].contains(entry.partOfSpeech) && seen.insert(entry.senseID).inserted {
                                let definition = entry.morphologicalTags["definition"] ?? ""
                                guard !["archaic","obsolete","slang","vulgar","rare"].contains(where:definition.localizedCaseInsensitiveContains) else { continue }
                                // An intransitive particle cannot swallow the start of a separate
                                // nominal complement: move [in unison], not residential [move in].
                                if phrase == "move in", range.upperBound < tokens.count,
                                   tokens[range.upperBound].sentenceIndex == tokens[start].sentenceIndex,
                                   ["noun","determiner","adjective"].contains(tokens[range.upperBound].pos) { continue }
                                let features: [String:String]
                                if entry.partOfSpeech == "verb" {
                                    guard let source = range.map({ tokens[$0] }).first(where:{$0.pos == "verb"}),
                                          let form = EnglishInflection.features(source,aggressive:true) else { continue }
                                    features = form
                                } else { features = [:] }
                                var attested: (LexicalEntry,String)?
                                for alternative in GrammaticalSenseResolver.alternatives(entry) {
                                    // Some dictionary phrase heads still require a complement:
                                    // in love -> verliebt in / влюблённый в is not a complete phrase.
                                    if entry.partOfSpeech == "prepositional_phrase", [" in"," an"," auf"," mit"," zu"," von"," в"," на"," с"," к"," о"].contains(where:alternative.hasSuffix) { continue }
                                    let variant = GrammaticalSenseResolver.replacingTarget(entry,alternative)
                                    guard let surface = try await pack.inflect(variant,features:features),
                                          try await pack.validateReplacement(variant,surface:surface,context:tokens[start].sentence) else { continue }
                                    attested = (variant,surface); break
                                }
                                // A recognized idiom without an attested finite form must not
                                // fall through to unrelated translations of its individual words.
                                if let attested { candidates.append(attested) }
                                else if entry.partOfSpeech == "verb" { candidates.append((entry,nil)) }
                            }
                        }
                        guard !candidates.isEmpty else { continue }
                        let chosen: Int?
                        if let selector {
                            candidates = Array(candidates.prefix(9))
                            let a = tokens[start].span.location, b = tokens[range.upperBound-1].span.location+tokens[range.upperBound-1].span.length
                            let sourceRange = try UTF16Span(location:a,length:b-a).range(in:text)
                            let lower = text.index(sourceRange.lowerBound,offsetBy:-180,limitedBy:text.startIndex) ?? text.startIndex
                            let upper = text.index(sourceRange.upperBound,offsetBy:180,limitedBy:text.endIndex) ?? text.endIndex
                            let marked = String(text[lower..<sourceRange.lowerBound])+"[["+String(text[sourceRange])+"]]"+String(text[sourceRange.upperBound..<upper])
                            chosen = try await selector.selectSense(.init(expression:words.joined(separator:" "),partOfSpeech:"expression",sentence:marked,languageCode:pack.metadata.languageCode,
                                options:candidates.map{ .init(definition:String(($0.0.morphologicalTags["definition"] ?? "").prefix(240)),target:$0.1 ?? $0.0.targetLemma) }))
                        } else { chosen = Set(candidates.map{$0.1}).count == 1 && candidates[0].0.partOfSpeech != "verb" ? 0 : nil }
                        if let chosen, candidates.indices.contains(chosen) {
                            recognizedRange = range
                            if let surface = candidates[chosen].1 {
                                selected.append(.init(range:range,entry:candidates[chosen].0,surface:surface,pack:pack))
                            }
                        }
                    }
                    if !selected.isEmpty || recognizedRange != nil { break }
                }
            }
            result += selected
            if let recognizedRange { protected.append(recognizedRange) }
            cursor = selected.first?.range.upperBound ?? recognizedRange?.upperBound ?? start+1
        }
        return .init(choices:result,protectedRanges:protected)
    }
}
