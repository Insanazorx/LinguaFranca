import Foundation

public struct ReplacementResult: Sendable {
    public let spans: [ReplacementSpan]
    public let wordCount: Int
    public let requestedDensity: Double
    public let actualDensity: Double
    public let languageCounts: [String: Int]
    public let eligibleWordCount: Int
    public let replacedWordCount: Int
    public let unresolved: [ReplacementGap]
    public var isComplete: Bool { unresolved.isEmpty }
}

public struct ReplacementGap: Sendable, Equatable {
    public let surface: String
    public let partOfSpeech: String
    public let range: UTF16Span
    public let contextExpression: String?
}

/// English analysis, lexical lookup and deterministic allocation are independent of inference and UI.
public struct ContextualReplacementEngine: Sendable {
    private let registry: LanguagePackRegistry
    private let senseSelector: (any ContextualSenseSelecting)?
    public init(registry: LanguagePackRegistry, senseSelector: (any ContextualSenseSelecting)? = nil) {
        self.registry = registry; self.senseSelector = senseSelector
    }

    public func replace(text: String, sourceTextID: String, settings: AppSettings, seed: UInt32) async throws -> ReplacementResult {
        try settings.validate()
        let tokens = EnglishAnalyzer.tokens(in: text,bundledTagger:registry.englishTagger)
        let frequencies = settings.replacementLanguageShares.filter { $0.value > 0 }
        let focused = settings.replacementMode == .aggressive
        func eligible(_ token: EnglishToken) -> Bool {
            focused ? settings.practiceDomains.contains(where: { $0.includes(token.pos) }) : ["noun", "adverb", "conjunction", "preposition", "pronoun"].contains(token.pos)
        }
        let phrases = focused ? PrepositionalPractice.patterns(tokens).filter {
            settings.practiceDomains.contains(.prepositionalPhrases) || (settings.practiceDomains.contains(.structure) && tokens[$0.indices.lowerBound].lemma == "of")
        } : []
        let predicates = focused && settings.practiceDomains.contains(.actions) ? VerbPhrasePractice.patterns(tokens) : []
        var reserved: Set<Int> = []
        let required = Set(tokens.indices.filter { eligible(tokens[$0]) }).union(settings.practiceDomains.contains(.prepositionalPhrases) ? phrases.flatMap { Array($0.indices) } : [])
        let eligibleCount = required.count
        let requested = focused ? Double(eligibleCount) / Double(max(1, tokens.count)) : frequencies.values.reduce(0, +)
        guard !tokens.isEmpty, requested > 0, !frequencies.isEmpty else {
            return ReplacementResult(spans: [], wordCount: tokens.count, requestedDensity: requested, actualDensity: 0, languageCounts: [:], eligibleWordCount: eligibleCount, replacedWordCount: 0, unresolved: [])
        }
        let packs = registry.packs.filter { frequencies[$0.metadata.languageCode] != nil }
        struct Choice {
            let entry: LexicalEntry
            let surface: String
            let pack: any LanguagePack
            let confidence: Double
        }
        var options: [Int: [Choice]] = [:]
        var phraseEnds: [Int:Int] = [:]
        var protectedExpressions: [Range<Int>] = []
        if focused, settings.practiceDomains.contains(.structure) {
            for range in IndirectQuestionPractice.ranges(tokens) {
                guard reserved.isDisjoint(with:range) else { continue }
                for pack in packs {
                    if let entry = try await IndirectQuestionPractice.entry(range,tokens:tokens,pack:pack,text:text) {
                        options[range.lowerBound,default:[]].append(Choice(entry:entry,surface:entry.targetLemma,pack:pack,confidence:0.94))
                        phraseEnds[range.lowerBound] = range.upperBound-1; reserved.formUnion(range)
                    }
                }
            }
        }
        for predicate in predicates {
            guard reserved.isDisjoint(with:predicate.indices) else { continue }
            let start = predicate.indices.lowerBound
            for pack in packs {
                if let entry = try await VerbPhrasePractice.entry(predicate,tokens:tokens,pack:pack,text:text) {
                    options[start,default:[]].append(Choice(entry:entry,surface:entry.targetLemma,pack:pack,confidence:0.94))
                    phraseEnds[start] = predicate.indices.upperBound-1
                    reserved.formUnion(predicate.indices)
                }
            }
        }
        if focused {
            let expressions = try await LexicalExpressionPractice.choices(tokens:tokens,text:text,required:required,packs:packs,selector:senseSelector,excluded:reserved)
            protectedExpressions = expressions.protectedRanges
            for range in protectedExpressions { reserved.formUnion(range) }
            for choice in expressions.choices {
                options[choice.range.lowerBound,default:[]].append(Choice(entry:choice.entry,surface:choice.surface,pack:choice.pack,confidence:0.92))
                phraseEnds[choice.range.lowerBound] = choice.range.upperBound-1; reserved.formUnion(choice.range)
            }
        }
        protectedExpressions += phrases.map(\.indices)
        for phrase in phrases {
            guard reserved.isDisjoint(with:phrase.indices) else { continue }
            try Task.checkCancellation()
            let start = phrase.indices.lowerBound
            for pack in packs {
                if let entry = try await PrepositionalPractice.entry(pattern: phrase, tokens: tokens, pack: pack, source: text, aggressive: focused, selector:senseSelector) {
                    var surface = entry.targetLemma
                    if tokens[start].isSentenceInitial, let first = surface.first { surface = String(first).uppercased() + surface.dropFirst() }
                    options[start, default: []].append(Choice(entry: entry, surface: surface, pack: pack, confidence: 0.94))
                    phraseEnds[start] = phrase.indices.upperBound - 1
                    reserved.formUnion(phrase.indices)
                }
            }
        }
        // Passage-local cache only; the lexicon itself stays on disk.
        var cache: [String: [LexicalEntry]] = [:]
        for (i, token) in tokens.enumerated() {
            try Task.checkCancellation()
            // Citation forms are only defensible for uninflected source nouns and invariant words.
            guard eligible(token), !reserved.contains(i),
                  token.pos != "pronoun" || token.surface.lowercased() == token.lemma,
                  !(token.pos == "adverb" && ["more","most","less","least"].contains(token.lemma)),
                  !(token.pos == "noun" && token.isPlural && ["that","which","who"].contains(token.previousWord ?? "")
                    && ["determiner","pronoun"].contains(token.followingPOS ?? "")),
                  !token.isCompoundComponent,
                  !token.surface.contains("’"), !token.surface.contains("'"),
                  let features = EnglishInflection.features(token, aggressive: focused) else { continue }
            for pack in packs where pack.supportsPartOfSpeech(token.pos) {
                let code = pack.metadata.languageCode
                let lemmas = EnglishInflection.lemmas(token)
                var resolutions: [SenseResolver.Resolution] = []
                var availableEntries: [LexicalEntry] = []
                for lemma in lemmas {
                    let key = code + ":" + lemma
                    let entries: [LexicalEntry]
                    if let found = cache[key] { entries = found }
                    else { entries = try await pack.lookup(englishLemma: lemma); cache[key] = entries }
                    availableEntries += entries
                    var source = token; source.lemma = lemma
                    let resolved = focused ? GrammaticalSenseResolver.resolve(entries, token: source, language: code) : SenseResolver.resolve(entries:entries,token:source)
                    if let resolved { resolutions.append(resolved) }
                }
                if resolutions.count != 1, focused, let senseSelector {
                    var candidates: [Choice] = [], seenSenses: Set<String> = []
                    let contextWords = SenseResolver.words(token.sentence)
                    let rankedEntries = availableEntries.enumerated().sorted {
                        let a = SenseResolver.words($0.element.morphologicalTags["definition"] ?? "").intersection(contextWords).count
                        let b = SenseResolver.words($1.element.morphologicalTags["definition"] ?? "").intersection(contextWords).count
                        return a == b ? $0.offset < $1.offset : a > b
                    }.map(\.element)
                    for entry in rankedEntries where entry.partOfSpeech == token.pos && seenSenses.insert(entry.senseID).inserted {
                        let definition = (entry.morphologicalTags["definition"] ?? "").lowercased()
                        guard !["archaic","obsolete","vulgar","offensive","slang","historical","rare","nonstandard"].contains(where:definition.contains) else { continue }
                        for alternative in GrammaticalSenseResolver.alternatives(entry) {
                            let variant = GrammaticalSenseResolver.replacingTarget(entry,alternative)
                            guard GrammaticalSenseResolver.permitsIsolated(variant,token:token,language:code) else { continue }
                            if let surface = try await pack.inflect(variant,features:features),
                               try await pack.validateReplacement(variant,surface:surface,context:token.sentence) {
                                candidates.append(Choice(entry:variant,surface:surface,pack:pack,confidence:0.8)); break
                            }
                        }
                        if candidates.count == 9 { break }
                    }
                    if !candidates.isEmpty {
                        let range = try token.span.range(in:text)
                        let start = text.index(range.lowerBound,offsetBy:-240,limitedBy:text.startIndex) ?? text.startIndex
                        let end = text.index(range.upperBound,offsetBy:240,limitedBy:text.endIndex) ?? text.endIndex
                        let marked = String(text[start..<range.lowerBound]) + " [[" + token.surface + "]] " + String(text[range.upperBound..<end])
                        let request = ContextualSenseRequest(expression:token.surface,partOfSpeech:token.pos,sentence:marked,languageCode:code,
                            options:candidates.map { .init(definition:String(($0.entry.morphologicalTags["definition"] ?? "").prefix(240)),target:$0.surface) })
                        if let index = try await senseSelector.selectSense(request), candidates.indices.contains(index) {
                            let selected = candidates[index]
                            var surface = selected.surface
                            if token.isSentenceInitial, let first = surface.first { surface = String(first).uppercased() + surface.dropFirst() }
                            options[i,default:[]].append(Choice(entry:selected.entry,surface:surface,pack:pack,confidence:selected.confidence))
                        }
                    }
                    continue
                }
                guard resolutions.count == 1, let resolved = resolutions.first else { continue }
                var inflected: (LexicalEntry,String)?
                let alternatives = focused ? GrammaticalSenseResolver.alternatives(resolved.entry) : [resolved.entry.targetLemma]
                for alternative in alternatives {
                    let entry = GrammaticalSenseResolver.replacingTarget(resolved.entry, alternative)
                    guard !focused || GrammaticalSenseResolver.permitsIsolated(entry,token:token,language:code) else { continue }
                    guard focused || LexicalContrastPolicy.isDistinct(english:entry.englishLemma,target:entry.targetLemma),
                          let form = try await pack.inflect(entry, features:features),
                          try await pack.validateReplacement(entry,surface:form,context:token.sentence) else { continue }
                    inflected = (entry,form); break
                }
                guard let (entry, form) = inflected else { continue }
                var surface = form
                // Preserve sentence-initial case. German dictionary noun capitals remain intact.
                if token.isSentenceInitial, let first = surface.first {
                    surface = String(first).uppercased() + surface.dropFirst()
                }
                guard focused || LexicalContrastPolicy.isDistinct(english: token.surface, target: surface) else { continue }
                options[i, default: []].append(Choice(entry: entry, surface: surface, pack: pack, confidence: resolved.confidence))
            }
        }
        let limit = focused ? options.count : min(Int((Double(tokens.count) * requested).rounded()), tokens.count / 2)
        var rng = SeededGenerator(seed: UInt64(seed)), order = Array(options.keys).sorted()
        order.shuffle(using: &rng)
        var selected: [Int: Choice] = [:], counts: [String: Int] = [:]
        // Prefer spaced words, then at high density allow pairs, never three in a row.
        let passes = !focused && requested >= 0.33 ? 2 : 1
        for pass in 0..<passes {
          for i in order where selected.count < limit {
            guard selected[i] == nil, let choices = options[i] else { continue }
            if !focused && pass == 0 {
                guard selected[i-1] == nil, selected[i+1] == nil else { continue }
            } else if !focused {
                guard !(selected[i-2] != nil && selected[i-1] != nil),
                      !(selected[i-1] != nil && selected[i+1] != nil),
                      !(selected[i+1] != nil && selected[i+2] != nil) else { continue }
            }
            let ranked = choices.sorted { a, b in
                let ac = a.pack.metadata.languageCode, bc = b.pack.metadata.languageCode
                let denominator = focused ? frequencies.values.reduce(0,+) : 1
                let target = focused ? Double(selected.count + 1) : Double(tokens.count)
                let ad = (frequencies[ac] ?? 0) / denominator * target - Double(counts[ac, default: 0])
                let bd = (frequencies[bc] ?? 0) / denominator * target - Double(counts[bc, default: 0])
                return ad == bd ? ac < bc : ad > bd
            }
            guard let chosen = ranked.first(where: {
                let code = $0.pack.metadata.languageCode
                return focused || Double(counts[code, default: 0]) < ((frequencies[code] ?? 0) * Double(tokens.count)).rounded()
            }) else { continue }
            selected[i] = chosen
            counts[chosen.pack.metadata.languageCode, default: 0] += 1
          }
        }
        var spans: [ReplacementSpan] = [], offset = 0, replacedWords = 0
        var covered: Set<Int> = []
        for i in selected.keys.sorted() {
            guard let choice = selected[i] else { continue }
            let token = tokens[i], code = choice.pack.metadata.languageCode, last = tokens[phraseEnds[i] ?? i]
            let sourceSpan = UTF16Span(location: token.span.location, length: last.span.location + last.span.length - token.span.location)
            let original = (text as NSString).substring(with: NSRange(location: sourceSpan.location, length: sourceSpan.length))
            replacedWords += (phraseEnds[i] ?? i) - i + 1
            covered.formUnion(i...(phraseEnds[i] ?? i))
            spans.append(ReplacementSpan(id: "\(sourceTextID)-\(token.span.location)-\(code)", sourceTextID: sourceTextID,
                originalUTF16Range: sourceSpan,
                renderedUTF16Range: UTF16Span(location: token.span.location + offset, length: choice.surface.utf16.count),
                originalSurface: original, originalLemma: choice.entry.englishLemma, originalPartOfSpeech: choice.entry.partOfSpeech,
                sourceSenseID: choice.entry.senseID, targetLanguageCode: code,
                targetLemma: choice.entry.targetLemma, targetSurface: choice.surface,
                translationConfidence: choice.confidence, languagePackVersion: choice.pack.metadata.version,
                senseDescription: SenseResolver.description(choice.entry)))
            offset += choice.surface.utf16.count - sourceSpan.length
        }
        return ReplacementResult(spans: spans, wordCount: tokens.count, requestedDensity: requested,
            actualDensity: Double(replacedWords) / Double(tokens.count), languageCounts: counts, eligibleWordCount: eligibleCount,
            replacedWordCount: covered.intersection(required).count,
            unresolved: focused ? required.subtracting(covered).sorted().map { i in
                let expression = protectedExpressions.first { $0.contains(i) }.map { $0.map { tokens[$0].surface }.joined(separator:" ") }
                return .init(surface:tokens[i].surface,partOfSpeech:tokens[i].pos,range:tokens[i].span,contextExpression:expression)
            } : [])
    }
}

struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum SenseResolver {
    struct Resolution { let entry: LexicalEntry; let confidence: Double }
    static func description(_ entry: LexicalEntry) -> String? {
        if entry.partOfSpeech == "conjunction" {
            switch entry.englishLemma {
            case "but": return "Contrasts two statements; not the 'except' meaning."
            case "if": return "Introduces a condition; not an indirect question."
            case "that": return "Introduces a content clause; not a relative clause."
            default: break
            }
        }
        return entry.morphologicalTags["definition"]
    }
    private static let stop = Set("a an the of to in on at by for from is are was were be being been as that this it its with without and or but one something someone having used use act state quality person thing very more most less little any not no than into their they his her our your my which who when where while during time period experience experiences way make part place".split(separator: " ").map(String.init))
    private static let blocked = ["obsolete", "archaic", "vulgar", "slang", "historical", "rare", "offensive", "derogatory"]
    // High-risk polysemes require positive contextual evidence; POS alone is insufficient.
    private static let senses: [String: [(Set<String>, Set<String>)]] = [
        "house": [(Set(["home","roof","kitchen","bedroom","door","window","garden","shelter"]), Set(["$general"])),
                  (Set(["parliament","legislature","debate","politician"]), Set(["chamber","government"]))],
        "hungry": [(Set(["food","meal","lunch","dinner","breakfast","eat","eating","stomach"]), Set(["$general"])),
                   (Set(["power","success","ambition","attention","fame"]), Set(["eager","desire"]))],
        "bank": [(Set(["money", "deposit", "loan", "account", "cash", "financial"]), Set(["institution", "financial", "branch"])),
                 (Set(["river", "stream", "water", "shore"]), Set(["river", "water", "slope", "land", "edge"]))],
        "light": [(Set(["lamp", "sun", "bright", "dark", "room", "shine"]), Set(["illumination", "radiation", "visible", "light"])),
                  (Set(["weight", "heavy", "carry", "bag"]), Set(["weight"]))],
        "charge": [(Set(["pay", "fee", "price", "bill", "cost"]), Set(["price", "fee", "payment", "money"])),
                   (Set(["crime", "court", "police", "accuse"]), Set(["accusation", "accuse", "offence", "crime"]))],
        "right": [(Set(["turn", "left", "direction", "road"]), Set(["direction", "left", "side"])),
                  (Set(["answer", "correct", "wrong"]), Set(["correct", "true"]))],
        "trip": [(Set(["journey", "travel", "destination", "route", "airport", "holiday", "vacation", "luggage"]), Set(["$general"])),
                 (Set(["drug", "hallucination", "psychedelic", "lsd"]), Set(["drug", "hallucination"]))],
        "travel": [(Set(["journey", "trip", "destination", "route", "forest", "country"]), Set(["traveling"])),
                   (Set(["machine", "piston", "mechanical", "stroke"]), Set(["mechanical", "machinery"]))],
        "air": [(Set(["forest", "wind", "weather", "breathe", "fresh", "crisp", "tree"]), Set(["atmosphere"])),
                (Set(["music", "opera", "song", "sing"]), Set(["song", "aria"]))],
        "wind": [(Set(["weather", "forest", "sky", "tree", "scent", "cold", "blow", "storm"]), Set(["movement"])),
                 (Set(["music", "orchestra", "brass"]), Set(["orchestra"]))],
        "pine": [(Set(["forest", "tree", "wood", "scent", "earth"]), Set(["tree", "wood"])),
                 (Set(["grief", "sad", "longing"]), Set(["longing"]))],
        "earth": [(Set(["forest", "pine", "wind", "soil", "ground", "scent"]), Set(["soil", "ground", "rock"])),
                  (Set(["electrical", "wire", "circuit"]), Set(["electrical"]))],
        "destination": [(Set(["journey", "trip", "travel", "route", "airport", "train"]), Set(["journey"]))],
        "leaf": [(Set(["tree", "forest", "green", "rustle", "branch", "plant"]), Set(["plant"])),
                   (Set(["book", "page", "read"]), Set(["book"]))],
        "branch": [(Set(["tree", "oak", "forest", "trunk"]), Set(["woody"])),
                     (Set(["company", "office", "bank"]), Set(["organization"]))],
        "map": [(Set(["route", "travel", "notebook", "road", "journey"]), Set(["visual"]))],
        "note": [(Set(["handwritten", "notebook", "write", "paper", "map"]), Set(["memorandum"])),
                   (Set(["music", "piano", "melody", "sing"]), Set(["musical"]))],
        "bag": [(Set(["pack", "packed", "travel", "luggage", "carry", "carried"]), Set(["flexible"]))],
        "crowd": [(Set(["people", "street", "follow", "following", "gather"]), Set(["$general"]))],
        "soul": [(Set(["honor", "honour", "spiritual", "inner", "faith"]), Set(["essence"])),
                   (Set(["music", "song", "jazz"]), Set(["music"]))],
        "tree": [(Set(["oak", "forest", "pine", "branch", "wood", "leaf"]), Set(["plant", "trunk"]))]
    ]
    static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split(whereSeparator: { !$0.isLetter }).map {
            let word = String($0)
            return word.count > 4 && word.hasSuffix("s") ? String(word.dropLast()) : word
        }.filter { $0.count > 2 && !stop.contains($0) })
    }
    static func resolve(entries: [LexicalEntry], token: EnglishToken) -> Resolution? {
        var available = entries.filter {
            $0.partOfSpeech == token.pos && !blocked.contains(where: ($0.morphologicalTags["definition"] ?? "").lowercased().contains)
        }
        guard !available.isEmpty else { return nil }
        let context = words(token.nearbyWords?.joined(separator: " ") ?? token.sentence).subtracting([token.lemma])
        var explicitlyResolved = false
        if let guarded = senses[token.lemma] {
            let matches = guarded.filter { !$0.0.isDisjoint(with: context) }
            guard matches.count == 1, let sense = matches.first else { return nil }
            available = available.filter {
                let definition = $0.morphologicalTags["definition"] ?? ""
                return sense.1.contains("$general") ? definition.isEmpty : !words(definition).isDisjoint(with: sense.1)
            }
            guard !available.isEmpty else { return nil }
            explicitlyResolved = true
        }
        if token.pos == "preposition" {
            // These are lexical insertions into an English frame, not full German/Russian
            // clauses. Do not inflect surrounding English or claim target-language grammar.
            switch token.lemma {
            case "through":
                guard !context.isDisjoint(with: ["forest", "door", "window", "tunnel", "road", "fog", "crowd", "park"]) else { return nil }
                available = available.filter { ($0.morphologicalTags["definition"] ?? "").contains("entering, then later exiting") }
            case "without": available = available.filter { $0.morphologicalTags["definition"] == "not having" }
            case "between":
                available = available.filter { $0.morphologicalTags["definition"] == "in the position or interval that separates two things" }
            case "with":
                guard context.isDisjoint(with: ["fight", "struggle", "oppose", "agree", "disagree"]) else { return nil }
                available = available.filter { $0.morphologicalTags["definition"] == "with" }
            case "in":
                guard ["forest","city","room","park","cafe","café","office","garden","box","cup","bag","house","car"].contains(token.followingNoun ?? "") else { return nil }
                available = available.filter { $0.morphologicalTags["definition"] == "contained by" }
            case "into":
                guard ["forest","city","room","park","office","garden","box","cup","bag","house","car"].contains(token.followingNoun ?? "") else { return nil }
                available = available.filter { $0.morphologicalTags["definition"] == "going inside" }
            case "on":
                guard ["table","floor","bench","ground","desk","page","paper","shelf"].contains(token.followingNoun ?? "") else { return nil }
                available = available.filter { $0.morphologicalTags["definition"] == "positioned at the upper surface of" }
            case "before":
                guard ["tree","oak","door","house","building","wall","statue"].contains(token.followingNoun ?? "") else { return nil }
                available = available.filter { $0.morphologicalTags["definition"] == "in front of in space" }
            default: return nil
            }
            explicitlyResolved = true
        }
        if token.pos == "pronoun" {
            switch token.lemma {
            case "i": available = available.filter { $0.morphologicalTags["definition"] == "personal pronoun" }
            case "he": available = available.filter { $0.morphologicalTags["definition"] == "personal pronoun \"he\"" }
            case "she": available = available.filter { $0.morphologicalTags["definition"] == "person" }
            case "we": break
            default: return nil // No guesses about object case, politeness or singular THEY.
            }
            explicitlyResolved = true
        }
        if token.pos == "adverb" {
            switch token.lemma {
            case "so":
                guard ["adjective", "adverb"].contains(token.followingPOS ?? "") else { return nil }
                available = available.filter { $0.morphologicalTags["definition"] == "to a particular extent" }
                explicitlyResolved = true
            case "however":
                guard token.sentence.range(of: #"(?:^|[.!?;,])\s*however\s*,"#, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
                available = available.filter { ($0.morphologicalTags["definition"] ?? "").isEmpty }
                explicitlyResolved = true
            case "only":
                guard !["yesterday", "today", "recently", "then"].contains(token.followingWord ?? "") else { return nil }
                available = available.filter { ["no more than", "without others or anything further; exclusively"].contains($0.morphologicalTags["definition"] ?? "") }
                explicitlyResolved = true
            case "often", "usually", "always", "sometimes", "never", "together":
                explicitlyResolved = true
            case "still": return nil
            case "where":
                guard ["forest","city","room","park","cafe","café","office","garden","house","village"].contains(token.previousWord ?? "") else { return nil }
                available = available.filter { $0.morphologicalTags["definition"] == "at or in which place" }
                explicitlyResolved = true
            default: break
            }
        }
        if token.pos == "conjunction" {
            // Exclude idioms and non-equivalent senses of common connective words.
            guard ["and", "or", "but", "although", "because", "whereas", "that", "if", "before", "after"].contains(token.lemma) else { return nil }
            let lower = token.sentence.lowercased()
            if token.lemma == "but" {
                guard !lower.contains("anything but"), !lower.contains("nothing but"), !lower.contains("not only") else { return nil }
                available = available.filter { ($0.morphologicalTags["definition"] ?? "") == "although" }
            } else if token.lemma == "and" {
                available = available.filter { ($0.morphologicalTags["definition"] ?? "").contains("connect two similar") }
            } else if token.lemma == "because" {
                available = available.filter { ($0.morphologicalTags["definition"] ?? "").contains("as known because") }
            } else if token.lemma == "although" {
                available = available.filter { $0.morphologicalTags["definition"] == "in spite of the fact that" }
            } else if token.lemma == "whereas" {
                available = available.filter { ($0.morphologicalTags["definition"] ?? "").contains("but in contrast") }
            } else if token.lemma == "that" {
                let matrix = Set(["think","thinks","thought","believe","believes","believed","feel","feels","felt","know","knows","knew","say","says","said","tell","tells","told","notice","notices","noticed","hear","hears","heard","hope","hopes","hoped","realize","realizes","realized","decide","decides","decided","conclude","concludes","concluded","show","shows","showed","argue","argues","argued"])
                guard matrix.contains(token.previousWord ?? "") else { return nil }
                available = available.filter { $0.morphologicalTags["definition"] == "connecting a noun clause" }
            } else if token.lemma == "if" {
                guard !["ask","asked","wonder","wondered","know","knew","whether"].contains(where: { context.contains($0) }) else { return nil }
                available = available.filter { $0.morphologicalTags["definition"] == "supposing that" }
            } else if token.lemma == "before" {
                available = available.filter { $0.morphologicalTags["definition"] == "in advance of the time when" }
            } else if token.lemma == "after" {
                available = available.filter { $0.morphologicalTags["definition"] == "signifies that the action of its clause takes place before the action of the other clause" }
            }
            explicitlyResolved = true
        }
        guard !available.isEmpty else { return nil }
        if available.count == 1, let entry = available.first,
           (entry.morphologicalTags["definition"] ?? "").isEmpty,
           let data = entry.morphologicalTags["alternatives"]?.data(using: .utf8),
           let alternatives = try? JSONDecoder().decode([String].self, from: data), alternatives.count > 1, !explicitlyResolved {
            return nil
        }
        let targets = Set(available.map(\.targetLemma))
        if targets.count == 1, let first = available.first {
            return Resolution(entry: first, confidence: 0.9)
        }
        var scored: [(LexicalEntry, Int)] = []
        for entry in available {
            let definition = entry.morphologicalTags["definition"] ?? ""
            let keywords = words(definition).subtracting([token.lemma])
            scored.append((entry, keywords.intersection(context).count))
        }
        scored.sort { a, b in
            if a.1 == b.1 { return a.0.senseID < b.0.senseID }
            return a.1 > b.1
        }
        if let first = scored.first, first.1 >= (explicitlyResolved ? 1 : 2),
           !scored.dropFirst().contains(where: { $0.1 == first.1 && $0.0.targetLemma != first.0.targetLemma }) {
            return Resolution(entry: first.0, confidence: 0.85)
        }
        // A single documented sense can list synonyms. Multiple unresolved meanings are skipped.
        if available.count == 1, let entry = available.first,
           !(entry.morphologicalTags["definition"] ?? "").isEmpty {
            return Resolution(entry: entry, confidence: 0.85)
        }
        return nil
    }
}
