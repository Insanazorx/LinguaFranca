import Foundation

public struct AggressiveModelTask: Sendable, Equatable {
    public let domains: Set<PracticeDomain>
    public let languages: [String]
    public let assignments: [String:String]
    public let repair: AggressiveRepair?
    public init(settings: AppSettings, repair: AggressiveRepair? = nil) throws {
        guard settings.replacementMode == .aggressive, !settings.practiceDomains.isEmpty, !settings.enabledLanguages.isEmpty else {
            throw DomainError.invalidInput("Choose at least one Aggressive component and language.")
        }
        domains=settings.practiceDomains; languages=settings.enabledLanguages.sorted(); self.repair=repair
        assignments=Dictionary(uniqueKeysWithValues:domains.map { ($0.rawValue,settings.aggressiveLanguage(for:$0)) })
    }
    public var instructions: String {
        let all=languages.map { SemiticLanguage(rawValue:$0)?.title ?? Locale(identifier:"en").localizedString(forLanguageCode:$0) ?? $0 }.joined(separator:", ")
        let rules=PracticeDomain.allCases.filter(domains.contains).map { domain in
            let code=assignments[domain.rawValue] ?? "auto"
            let name=code == "auto" ? "distribute occurrences among all selected languages: " + all : (SemiticLanguage(rawValue:code)?.title ?? Locale(identifier:"en").localizedString(forLanguageCode:code) ?? code)
            return "\(domain.detail): \(name)."
        }.joined(separator:" ")
        let base="Create a bilingual grammar exercise. Keep English word order. Translate EVERY occurrence in each selected category, including repeated words, auxiliary verbs, conjunctions and prepositions. Other categories stay English. \(rules) Use context to choose the correct sense, tense, number and case. Preposition+object mode replaces the WHOLE governed phrase, including its object, as one unit. Do not overlap units. Output JSON only. "
        if let repair {
            let tokens=EnglishAnalyzer.tokens(in:repair.english)
            let slots=repair.slots.enumerated().map { index,slot in
                let sentence=tokens.first { $0.span.location == slot.range.location }?.sentence ?? repair.english
                let language=Locale(identifier:"en").localizedString(forLanguageCode:slot.language) ?? slot.language
                let choices=slot.attestedOptions.map { "\($0.surface) = \($0.definition)" }.joined(separator:"; ")
                return "Item \(index): English span \"\(slot.source)\". Category: \(slot.partOfSpeech). Target: \(language). Context: \(sentence)" + (choices.isEmpty ? "" : " Choose ONLY a supplied attested equivalent: " + choices)
            }.joined(separator:"\n")
            return "Translate each English span into its requested language. Use its sentence to choose the precise meaning and inflected form. The supplied grammatical category is binding: causal conjunctions must stay causal, temporal conjunctions temporal, and spatial prepositions spatial. Do not translate a conjunction as a preposition merely because the English spelling is the same. Keep the subject gender, person, tense and aspect of verbs. Translate ONLY that span, not the sentence or nearby words. For a conjunction or preposition, output ONLY the equivalent conjunction or preposition, without adding its object. For a whole phrase, include the governed object and case. Do not add English, labels, brackets, language codes, explanations or glosses to the translation. Return the exact requested JSON array of objects with source and target.\n\(slots)"
        }
        return base + "Write an original English text, rich to an extreme degree in ALL selected categories. Return {\"english\":\"complete original English text\",\"replacements\":[{\"source\":\"exact English span\",\"target\":\"contextually inflected target expression\",\"language\":\"language code\",\"occurrence\":0}]}. Occurrence is the zero-based occurrence of that exact source span in the English original. Include EVERY selected occurrence. Never put target words inside english. Syriac (syc) mappings are supplied separately by the corpus backend: leave those out; never invent Syriac text. No title or explanation. "
    }
    public var grammar: String {
        let string = #"""
        string ::= "\"" ([^"\\\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4}))* "\""
        """#
        if let repair {
            func literal(_ value:String) -> String {
                let encoded=String(decoding:try! JSONEncoder().encode(value),as:UTF8.self)
                return String(decoding:try! JSONEncoder().encode(encoded),as:UTF8.self)
            }
            let sequence=repair.slots.enumerated().map { "slot\($0.offset)" }.joined(separator:#" ws "," ws "#)
            let rules: String = repair.slots.enumerated().map { (index,slot) -> String in
                if !slot.attestedOptions.isEmpty {
                    let choices=slot.attestedOptions.map { literal($0.surface) }.joined(separator:" | ")
                    return "slot\(index) ::= \"{\" ws \"\\\"source\\\":\" ws \(literal(slot.source)) ws \",\" ws \"\\\"target\\\":\" ws target\(index) ws \"}\"\ntarget\(index) ::= \(choices)"
                }
                let letters=(slot.writingProfile ?? .standard(slot.language)).grammarLetters
                return "slot\(index) ::= \"{\" ws \"\\\"source\\\":\" ws \(literal(slot.source)) ws \",\" ws \"\\\"target\\\":\" ws target\(index) ws \"}\"\ntarget\(index) ::= \"\\\"\" word\(index) (\" \" word\(index)){0,19} \"\\\"\"\nword\(index) ::= [\(letters)]{1,48} ([’'-] [\(letters)]{1,24})?"
            }.joined(separator:"\n")
            return "root ::= \"[\" ws \(sequence) ws \"]\"\nws ::= [ \\t\\n\\r]*\n" + rules + "\n"
        }
        let generated=languages.filter { $0 != "syc" }
        if generated.isEmpty {
            return #"""
            root ::= "{" ws "\"english\":" ws string ws "," ws "\"replacements\":" ws "[]" ws "}"
            ws ::= [ \t\n\r]*
            """# + "\n" + string
        }
        let codes=generated.map { "\"\\\"\($0)\\\"\"" }.joined(separator:" | ")
        return #"""
        root ::= "{" ws "\"english\":" ws string ws "," ws "\"replacements\":" ws "[" ws (item (ws "," ws item)*)? ws "]" ws "}"
        item ::= "{" ws "\"source\":" ws string ws "," ws "\"target\":" ws string ws "," ws "\"language\":" ws language ws "," ws "\"occurrence\":" ws [0-9]{1,3} ws "}"
        ws ::= [ \t\n\r]*
        """# + "\nlanguage ::= \(codes)\n" + string
    }
}

public struct AggressiveRepair: Sendable, Equatable {
    public let english: String
    public let slots: [AggressiveSlot]
}
public struct AggressiveSlot: Sendable, Equatable {
    public let source: String
    public let range: UTF16Span
    public var language: String
    public let partOfSpeech: String
    public var attestedOptions: [AggressiveAttestedOption] = []
    public var writingProfile: LanguageWritingProfile? = nil
}
public struct AggressiveAttestedOption: Sendable, Equatable {
    public let surface:String
    public let definition:String
    public let lexemeID:String
    public let rootID:String?
    public let source:String
    public let packVersion:String
}
public struct AggressiveDraft: Codable, Sendable {
    public struct Mapping: Codable, Sendable {
        public let source: String
        public let target: String
        public let language: String
        public let occurrence: Int
    }
    public let english: String
    public let replacements: [Mapping]
    public static func decode(_ json: String) throws -> Self {
        guard let data=json.data(using:.utf8), data.count < 100_000,
              let value=try? JSONDecoder().decode(Self.self,from:data) else { throw GenerationError.invalidOutput("incomplete bilingual JSON") }
        return value
    }
    /// The source field precedes mappings. If the output budget ends inside mappings, keep the
    /// complete source and every complete mapping; repair only missing/invalid occurrences.
    public static func decodeRetainingSource(_ json:String) throws -> Self {
        guard json.utf8.count<100_000 else {throw GenerationError.invalidOutput("bilingual output is too large")}
        if let complete=try? decode(json) { return complete }
        let pattern = #"^\s*\{\s*"english"\s*:\s*("(?:[^"\\]|\\.)*")"#
        let regex=try NSRegularExpression(pattern:pattern)
        guard let match=regex.firstMatch(in:json,range:NSRange(json.startIndex...,in:json)),
              let range=Range(match.range(at:1),in:json),
              let english=try? JSONDecoder().decode(String.self,from:Data(json[range].utf8)) else {
            throw GenerationError.invalidOutput("no complete English source in bilingual output")
        }
        return .init(english:english,replacements:completeMappings(in:String(json[range.upperBound...])))
    }
    private static func completeMappings(in tail:String) -> [Mapping] {
        guard let expression=try? NSRegularExpression(pattern:#"^\s*,\s*"replacements"\s*:\s*\["#),
              let match=expression.firstMatch(in:tail,range:NSRange(tail.startIndex...,in:tail)),
              let header=Range(match.range,in:tail) else{return []}
        let decoder=JSONDecoder()
        var cursor=header.upperBound,mappings:[Mapping]=[]
        func skipWhitespace(_ position:inout String.Index) {
            while position<tail.endIndex && tail[position].isWhitespace {position=tail.index(after:position)}
        }
        while mappings.count<1000 {
            skipWhitespace(&cursor)
            guard cursor<tail.endIndex,tail[cursor]=="{" else {break}
            var scan=cursor,depth=0,inString=false,escaped=false,end:String.Index?
            while scan<tail.endIndex {
                let character=tail[scan]
                if inString {
                    if escaped {escaped=false}
                    else if character=="\\" {escaped=true}
                    else if character=="\"" {inString=false}
                } else if character=="\"" {inString=true}
                else if character=="{" {depth+=1}
                else if character=="}" {
                    depth-=1
                    if depth==0 {end=tail.index(after:scan);break}
                }
                scan=tail.index(after:scan)
            }
            guard let end,let mapping=try? decoder.decode(Mapping.self,from:Data(tail[cursor..<end].utf8)) else {break}
            mappings.append(mapping);cursor=end;skipWhitespace(&cursor)
            guard cursor<tail.endIndex,tail[cursor]=="," else {break}
            cursor=tail.index(after:cursor)
        }
        return mappings
    }
}

/// Uses the same original-English analysis as the dictionary engine. Inference cannot silently
/// skip a selected occurrence or change any unselected text. Meaning remains model-generated.
public struct AggressiveCoverageValidator: Sendable {
    private let tagger: BundledEnglishTagger?
    private let registry: LanguagePackRegistry?
    public init(registry: LanguagePackRegistry) { tagger=registry.englishTagger;self.registry=registry }
    public init() { tagger=nil;registry=nil }
    /// Reuse the existing, tested function-word sense rules as a cross-check. This never
    /// gates unfamiliar model-generated verbs/nouns on dictionary coverage.
    public func confirmedFunctionTargets(english:String,slots:[AggressiveSlot]) async throws -> [Int:String] {
        guard let registry else { return [:] }
        let tokens=EnglishAnalyzer.tokens(in:english,bundledTagger:tagger)
        var targets:[Int:String]=[:]
        for (index,slot) in slots.enumerated() where ["conjunction","preposition"].contains(slot.partOfSpeech) {
            guard var token=tokens.first(where: { $0.span == slot.range }),
                  let pack=registry.packs.first(where: { $0.metadata.languageCode == slot.language }) else { continue }
            token.pos=slot.partOfSpeech
            let entries=try await pack.lookup(englishLemma:token.lemma)
            guard let resolved=GrammaticalSenseResolver.resolve(entries,token:token,language:slot.language),
                  resolved.confidence >= 0.8,
                  GrammaticalSenseResolver.permitsIsolated(resolved.entry,token:token,language:slot.language),
                  try await pack.validateReplacement(resolved.entry,surface:resolved.entry.targetLemma,context:token.sentence) else { continue }
            let surface=resolved.entry.targetLemma
            if Self.validTarget(surface,slot:slot) { targets[index]=surface }
        }
        return targets
    }
    public func slots(english: String, task: AggressiveModelTask) -> [AggressiveSlot] {
        var tokens=EnglishAnalyzer.tokens(in:english,bundledTagger:tagger)
        // The bundled tagger sometimes labels clause-introducing "until" or "yet" as
        // a preposition/adverb. Correct only explicit subject + finite-verb clauses here.
        for i in tokens.indices where ["before","after","since","as","for","until","while","yet"].contains(tokens[i].surface.lowercased()) {
            var next=i+1
            if next < tokens.count, tokens[next].pos == "determiner" { next += 1 }
            while next < tokens.count, tokens[next].pos == "adjective" { next += 1 }
            if next+1 < tokens.count, tokens[next+1].sentenceIndex == tokens[i].sentenceIndex,
               ["noun","pronoun","propernoun"].contains(tokens[next].pos), tokens[next+1].pos == "verb",
               !["VBG","VBN","VB"].contains(tokens[next+1].pennTag ?? "") { tokens[i].pos="conjunction" }
        }
        var slots: [AggressiveSlot]=[], covered: Set<Int>=[]
        if task.domains.contains(.prepositionalPhrases) {
            for phrase in PrepositionalPractice.patterns(tokens) {
                var end=phrase.indices.upperBound
                // Include compound heads such as "the garden gate" and "a stone bench".
                while end < tokens.count, tokens[end].sentenceIndex == tokens[phrase.indices.lowerBound].sentenceIndex,
                      ["noun","propernoun"].contains(tokens[end].pos),
                      let previous=try? tokens[end-1].span.range(in:english), let next=try? tokens[end].span.range(in:english),
                      english[previous.upperBound..<next.lowerBound].allSatisfy(\.isWhitespace) { end += 1 }
                let indices=phrase.indices.lowerBound..<end
                guard covered.isDisjoint(with:indices) else { continue }
                let first=tokens[indices.lowerBound], last=tokens[indices.upperBound-1]
                let span=UTF16Span(location:first.span.location,length:last.span.location+last.span.length-first.span.location)
                if let range=try? span.range(in:english) {
                    slots.append(.init(source:String(english[range]),range:span,language:task.assignments[PracticeDomain.prepositionalPhrases.rawValue]!,partOfSpeech:"expression")); covered.formUnion(indices)
                }
            }
        }
        if task.domains.contains(.actions) {
            var predicates=VerbPhrasePractice.patterns(tokens).filter { $0.kind != "copula-adjective" }.map(\.indices)
            for i in tokens.indices where tokens[i].pos == "verb" {
                let head=tokens[i].surface.lowercased()
                var end=i+1
                if end < tokens.count, tokens[end].surface.lowercased() == "not" { end += 1 }
                guard end < tokens.count, tokens[end].sentenceIndex == tokens[i].sentenceIndex, tokens[end].pos == "verb" else { continue }
                if ["do","does","did"].contains(head) || (["have","has","had"].contains(head) && (tokens[end].pennTag == "VBN" || tokens[end].surface.lowercased() != tokens[end].lemma)) {
                    predicates.append(i..<(end+1))
                }
            }
            for indices in predicates where covered.isDisjoint(with:indices) {
                let first=tokens[indices.lowerBound],last=tokens[indices.upperBound-1]
                let span=UTF16Span(location:first.span.location,length:last.span.location+last.span.length-first.span.location)
                if let range=try? span.range(in:english) {
                    slots.append(.init(source:String(english[range]),range:span,language:task.assignments[PracticeDomain.actions.rawValue]!,partOfSpeech:"verb phrase"));covered.formUnion(indices)
                }
            }
        }
        for (index,token) in tokens.enumerated() where !covered.contains(index) {
            guard let domain=PracticeDomain.allCases.first(where: { task.domains.contains($0) && $0.includes(token.pos) }) else { continue }
            slots.append(.init(source:token.surface,range:token.span,language:task.assignments[domain.rawValue]!,partOfSpeech:token.pos))
        }
        var automaticIndex=0
        return slots.sorted { $0.range.location < $1.range.location }.map { original in
            var slot=original
            if slot.language == "auto" {
                slot.language=task.languages[automaticIndex % task.languages.count]; automaticIndex += 1
            }
            slot.writingProfile=registry?.packs.first(where: { $0.metadata.languageCode == slot.language })?.metadata.effectiveWritingProfile
            return slot
        }
    }
    public func syriacHints(domains:Set<PracticeDomain>) async throws -> [GenerationVocabularyHint] {
        guard let pack=registry?.packs.first(where: { $0.metadata.languageCode == "syc" }) else { return [] }
        let pool=["and","in","with","before","write","go","see","speak","house","water","man","woman","good","great"]
        var result:[GenerationVocabularyHint]=[]
        for lemma in pool {
            let entries=try await pack.lookup(englishLemma:lemma)
            if entries.contains(where: { entry in
                entry.provenance["source"]?.hasPrefix("ETCBC") == true && domains.contains(where: { $0.includes(entry.partOfSpeech) || ($0 == .prepositionalPhrases && entry.partOfSpeech == "preposition") })
            }) { result.append(.init(englishLemma:lemma,languageCode:"syc")) }
        }
        return result
    }
    /// Syriac is a constrained selection among actual corpus entries, never free model prose.
    /// Automatic allocation rebalances to another selected language when a corpus entry is absent.
    public func preparedSlots(english:String,task:AggressiveModelTask) async throws -> [AggressiveSlot] {
        var result=try await functionOptions(slots(english:english,task:task),english:english)
        guard task.languages.contains("syc"),let pack=registry?.packs.first(where: { $0.metadata.languageCode == "syc" }) else { return result }
        let tokens=EnglishAnalyzer.tokens(in:english,bundledTagger:tagger)
        func options(_ slot:AggressiveSlot) async throws -> [AggressiveAttestedOption] {
            let token=tokens.first { $0.span == slot.range }
            let lemmas=token.map(EnglishInflection.lemmas) ?? [slot.source.lowercased()]
            var entries:[LexicalEntry]=[]
            for lemma in lemmas { entries += try await pack.lookup(englishLemma:lemma) }
            var seen:Set<String>=[],values:[AggressiveAttestedOption]=[]
            for entry in entries where entry.partOfSpeech == slot.partOfSpeech && entry.provenance["source"]?.hasPrefix("ETCBC") == true {
                let features=token.flatMap { EnglishInflection.features($0,aggressive:true) }
                let inflected:String?
                if let features { inflected=try await pack.inflect(entry,features:features) } else { inflected=nil }
                let surface=inflected ?? entry.targetLemma
                guard SemiticUnicode.scriptMatches(surface,language:"syc"),seen.insert(surface).inserted else { continue }
                values.append(.init(surface:surface,definition:entry.morphologicalTags["definition"] ?? slot.source,lexemeID:entry.senseID,rootID:entry.morphologicalTags["rootID"],source:entry.provenance["url"] ?? "ETCBC Syriac Corpus",packVersion:pack.metadata.version))
                if values.count == 8 { break }
            }
            return values
        }
        let fallback=task.languages.filter { $0 != "syc" }
        for index in result.indices where result[index].language == "syc" {
            result[index].attestedOptions=try await options(result[index])
            if result[index].attestedOptions.isEmpty, !fallback.isEmpty {
                result[index].language=fallback[index % fallback.count]
            }
        }
        if !result.contains(where: { $0.language == "syc" }) {
            for index in result.indices {
                let values=try await options(result[index])
                if !values.isEmpty { result[index].language="syc";result[index].attestedOptions=values;break }
            }
        }
        return try await functionOptions(result,english:english)
    }
    private func functionOptions(_ input:[AggressiveSlot],english:String) async throws -> [AggressiveSlot] {
        guard let registry else { return input }
        var result=input
        for index in result.indices where result[index].language != "syc" && ["conjunction","preposition"].contains(result[index].partOfSpeech) {
            let slot=result[index]
            guard let pack=registry.packs.first(where: { $0.metadata.languageCode == slot.language }) else { continue }
            let entries=try await pack.lookup(englishLemma:slot.source.lowercased())
            var values:[AggressiveAttestedOption]=[],seen:Set<String>=[]
            for entry in entries where entry.partOfSpeech == slot.partOfSpeech {
                let definition=entry.morphologicalTags["definition"] ?? ""
                guard !["archaic","obsolete","vulgar","slang","rare","offensive"].contains(where:definition.localizedCaseInsensitiveContains) else { continue }
                for surface in GrammaticalSenseResolver.alternatives(entry) {
                    guard Self.validTarget(surface,slot:slot),seen.insert(surface).inserted else { continue }
                    values.append(.init(surface:surface,definition:String(definition.prefix(180)),lexemeID:entry.senseID,rootID:entry.morphologicalTags["rootID"],source:entry.provenance["url"] ?? "Local language pack",packVersion:pack.metadata.version))
                    if values.count >= 12 { break }
                }
                if values.count >= 12 { break }
            }
            result[index].attestedOptions=values
        }
        return result
    }
    public func targets(_ draft: AggressiveDraft, task: AggressiveModelTask) -> [UTF16SpanKey:String] {
        var result:[UTF16SpanKey:String]=[:]
        for map in draft.replacements {
            guard map.occurrence >= 0, !map.source.isEmpty else { continue }
            let matches=Self.occurrences(map.source,in:draft.english)
            guard matches.indices.contains(map.occurrence) else { continue }
            let range=matches[map.occurrence]
            let key=UTF16SpanKey(range:range,language:map.language)
            // Duplicated mappings are rejected rather than choosing an arbitrary translation.
            if result[key] != nil { result[key]="" } else { result[key]=map.target }
        }
        return result
    }
    public static func validTarget(_ target: String, slot: AggressiveSlot) -> Bool {
        let clean=target.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !clean.isEmpty, clean == target, clean.count <= 160, !clean.contains("<"), !clean.contains("\n"),
              !clean.contains("="), !clean.contains(":"), !clean.contains("["), !clean.contains("]"), !clean.contains("(") else { return false }
        let letters=clean.unicodeScalars.filter(CharacterSet.letters.contains)
        guard !letters.isEmpty else { return false }
        if !slot.attestedOptions.isEmpty, !slot.attestedOptions.contains(where: { $0.surface == clean }) { return false }
        switch slot.language {
        case "ru": return letters.allSatisfy { (0x400...0x52f).contains($0.value) }
        case "ar", "he": return SemiticUnicode.scriptMatches(clean,language:slot.language)
        case "syc": return slot.attestedOptions.contains(where: { $0.surface == clean }) && SemiticUnicode.scriptMatches(clean,language:"syc")
        case "de": return letters.allSatisfy { $0.isASCII || "äöüÄÖÜßẞ".unicodeScalars.contains($0) }
        default:
            guard slot.writingProfile != nil || ["la","es","fr"].contains(slot.language) else { return false }
            return (slot.writingProfile ?? .standard(slot.language)).accepts(clean)
        }
    }
    public func reading(english: String, slots: [AggressiveSlot], targets: [String], request: GenerationRequest, result: GenerationResult, sourceID: String = UUID().uuidString) throws -> GeneratedText {
        guard slots.count == targets.count, zip(slots,targets).allSatisfy({ Self.validTarget($0.1,slot:$0.0) }) else { throw GenerationError.invalidOutput("one or more selected components have no valid target expression") }
        var spans:[ReplacementSpan]=[], delta=0
        let contextTokens=EnglishAnalyzer.tokens(in:english,bundledTagger:tagger)
        for (slot,target) in zip(slots,targets) {
            let context=contextTokens.first { $0.span.location == slot.range.location }?.sentence ?? slot.source
            let attestation=slot.attestedOptions.first { $0.surface == target }
            let reference=SemiticLanguage(rawValue:slot.language) == nil ? nil : attestation.map { SemiticVocabularyReference(languageCode:slot.language,kind:.lexeme,rootID:$0.rootID,lexemeID:$0.lexemeID) }
            spans.append(.init(sourceTextID:sourceID,originalUTF16Range:slot.range,renderedUTF16Range:.init(location:slot.range.location+delta,length:target.utf16.count),originalSurface:slot.source,originalLemma:slot.source.lowercased(),originalPartOfSpeech:slot.partOfSpeech,sourceSenseID:attestation?.lexemeID ?? "local-model:\(slot.source.lowercased()):\(String(context.prefix(240)))",targetLanguageCode:slot.language,targetLemma:target,targetSurface:target,translationConfidence:0.5,languagePackVersion:attestation?.packVersion ?? "model:\(result.modelIdentifier)",senseDescription:attestation?.definition ?? "Contextual expression generated by the local model",lexicalReference:reference))
            delta += target.utf16.count-slot.range.length
        }
        var metadata=result.metadata
        metadata["replacementMode"]="aggressive"; metadata["replacementStatus"]="local-model"; metadata["replacementComplete"]="true"
        metadata["translationValidation"]="coverage-script-and-local-function-checks"; metadata["wordCount"]=String(english.split(whereSeparator:\.isWhitespace).count); metadata["eligibleWordCount"]=String(slots.count); metadata["replacedWordCount"]=String(slots.count)
        metadata["practiceDomains"]=request.aggressiveDomains.map(\.rawValue).sorted().joined(separator:",")
        metadata["durationSeconds"]=String(result.duration); metadata["tokenCount"]=String(result.tokenCount)
        for (code,group) in Dictionary(grouping:spans,by:\.targetLanguageCode) { metadata["replacementCount."+code]=String(group.count) }
        metadata["unrepresentedLanguages"]=(request.aggressiveTask?.languages ?? request.targetLanguageCodes).filter { code in !spans.contains { $0.targetLanguageCode == code } }.joined(separator:",")
        let reading=GeneratedText(id:sourceID,originalEnglish:english,topic:request.topic,cefrLevel:request.level,modelID:result.modelIdentifier,seed:request.seed,metadata:metadata,replacements:spans)
        _ = try reading.renderedText()
        return reading
    }
    static func occurrences(_ source:String,in text:String) -> [UTF16Span] {
        var ranges:[UTF16Span]=[], cursor=text.startIndex
        while cursor < text.endIndex, let range=text.range(of:source,range:cursor..<text.endIndex) {
            let before=range.lowerBound == text.startIndex ? nil : text[text.index(before:range.lowerBound)]
            let after=range.upperBound == text.endIndex ? nil : text[range.upperBound]
            if before?.isLetter != true && after?.isLetter != true {
                let ns=NSRange(range,in:text); ranges.append(.init(location:ns.location,length:ns.length))
            }
            cursor=range.upperBound
        }
        return ranges
    }
}
public struct UTF16SpanKey: Hashable, Sendable {
    public let location:Int, length:Int, language:String
    public init(range:UTF16Span,language:String) { location=range.location;length=range.length;self.language=language }
}

public struct AggressiveReadingGenerator: Sendable {
    let model:any TextGenerationService
    let validator:AggressiveCoverageValidator
    public init(model:any TextGenerationService,registry:LanguagePackRegistry) { self.model=model;validator = .init(registry:registry) }
    public func generate(request:GenerationRequest,settings:AppSettings,sourceReady:@Sendable (GeneratedText) async -> Void = {_ in}) async throws -> GeneratedText {
        let task=try AggressiveModelTask(settings:settings)
        var direct=request;
        direct.targetLanguageCodes=task.languages
        if task.languages.contains("syc") { direct.vocabularyHints += try await validator.syriacHints(domains:task.domains) }; direct.aggressiveTask=task
        direct.configuration.contextWindow=4096;direct.configuration.maximumTokens=1536
        let start=ContinuousClock.now
        let raw=try await model.generate(request:direct)
        let draft=try AggressiveDraft.decode(raw.englishText)
        let english=try PassageValidator.validate(draft.english,requestedWords:request.wordCount,genre:request.genre)
        try PassageNoveltyValidator.validate(english,previous:request.previousPassages)
        let sourceID=UUID().uuidString
        var sourceMetadata=raw.metadata;sourceMetadata["replacementMode"]="aggressive";sourceMetadata["replacementStatus"]="processing"
        await sourceReady(.init(id:sourceID,originalEnglish:english,topic:request.topic,cefrLevel:request.level,modelID:raw.modelIdentifier,seed:request.seed,metadata:sourceMetadata))
        let slots=try await validator.preparedSlots(english:english,task:task), supplied=validator.targets(draft,task:task)
        guard !slots.isEmpty else { throw GenerationError.invalidOutput("the generated text contains none of the selected components") }
        var targets=slots.map { supplied[UTF16SpanKey(range:$0.range,language:$0.language)] ?? "" }
        let confirmed=try await validator.confirmedFunctionTargets(english:english,slots:slots)
        for (index,target) in confirmed { targets[index]=target }
        for (index,slot) in slots.enumerated() where slot.attestedOptions.count == 1 { targets[index]=slot.attestedOptions[0].surface }
        var tokens=raw.tokenCount, repaired=0
        let missing=slots.indices.filter { !AggressiveCoverageValidator.validTarget(targets[$0],slot:slots[$0]) }
        // Repair only uncovered occurrences, in bounded batches. Every response has an exact item count.
        for offset in stride(from:0,to:missing.count,by:8) {
            try Task.checkCancellation()
            let indices=Array(missing[offset..<min(offset+8,missing.count)])
            var repair=request; repair.previousPassages=[]
            repair.configuration.contextWindow=4096;repair.configuration.maximumTokens=512;repair.configuration.temperature=0.2
            repair.aggressiveTask=try .init(settings:settings,repair:.init(english:english,slots:indices.map { slots[$0] }))
            let output=try await model.generate(request:repair); tokens += output.tokenCount
            let values=try repair.aggressiveTask!.repair!.targets(from:output.englishText)
            guard values.count == indices.count else { throw GenerationError.invalidOutput("missing repair entries") }
            for (index,value) in zip(indices,values) { targets[index]=value; repaired += 1 }
        }
        let duration=start.duration(to:.now)
        var meta=raw.metadata;meta["repairedOccurrences"]=String(repaired);meta["dictionaryFunctionChecks"]=String(confirmed.count)
        let result=GenerationResult(englishText:english,duration:Double(duration.components.seconds)+Double(duration.components.attoseconds)/1e18,modelIdentifier:raw.modelIdentifier,seed:raw.seed,tokenCount:tokens,metadata:meta)
        return try validator.reading(english:english,slots:slots,targets:targets,request:direct,result:result,sourceID:sourceID)
    }
    public func remix(_ passage:GeneratedText,settings:AppSettings) async throws -> GeneratedText {
        let task=try AggressiveModelTask(settings:settings)
        let slots=try await validator.preparedSlots(english:passage.originalEnglish,task:task)
        guard !slots.isEmpty else { throw GenerationError.invalidOutput("this text has none of the selected components") }
        var targets:[String]=[],tokens=0
        let start=ContinuousClock.now
        var modelID="Qwen3.5-2B-Q4_K_M"
        for offset in stride(from:0,to:slots.count,by:8) {
            var request=GenerationRequest(topic:passage.topic,level:passage.cefrLevel,seed:passage.seed,aggressiveDomains:settings.practiceDomains)
            request.aggressiveTask=try .init(settings:settings,repair:.init(english:passage.originalEnglish,slots:Array(slots[offset..<min(offset+8,slots.count)])))
            request.configuration.contextWindow=4096;request.configuration.maximumTokens=512;request.configuration.temperature=0.2
            let output=try await model.generate(request:request)
            targets += try request.aggressiveTask!.repair!.targets(from:output.englishText); tokens += output.tokenCount;modelID=output.modelIdentifier
        }
        let confirmed=try await validator.confirmedFunctionTargets(english:passage.originalEnglish,slots:slots)
        for (index,target) in confirmed { targets[index]=target }
        let elapsed=start.duration(to:.now)
        let result=GenerationResult(englishText:passage.originalEnglish,duration:Double(elapsed.components.seconds)+Double(elapsed.components.attoseconds)/1e18,modelIdentifier:modelID,seed:passage.seed,tokenCount:tokens,metadata:passage.metadata)
        return try validator.reading(english:passage.originalEnglish,slots:slots,targets:targets,request:.init(topic:passage.topic,level:passage.cefrLevel,seed:passage.seed,targetLanguageCodes:settings.enabledLanguages,aggressiveDomains:settings.practiceDomains),result:result,sourceID:passage.id)
    }
}
public struct AggressiveRepairTarget: Codable, Sendable { public let source:String; public let target:String }
public extension AggressiveRepair {
    func targets(from json:String) throws -> [String] {
        guard let values=try? JSONDecoder().decode([AggressiveRepairTarget].self,from:Data(json.utf8)),
              values.count == slots.count, zip(values,slots).allSatisfy({ $0.source == $1.source }) else {
            throw GenerationError.invalidOutput("repair expressions do not match their original spans")
        }
        return values.map(\.target)
    }
}
