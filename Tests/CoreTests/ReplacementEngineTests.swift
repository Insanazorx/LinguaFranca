import Foundation
import Testing
@testable import LinguaFrancaCore

private var packDirectory: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Resources/LanguagePacks")
}

@Test func frequencyMigrationZeroAndFutureLanguages() throws {
    let old = Data(#"{"enabledLanguages":["de","ru"],"languageWeights":{"de":0.3,"ru":0.7},"replacementDensity":"high"}"#.utf8)
    var settings = try JSONDecoder().decode(AppSettings.self, from: old)
    #expect(abs(settings.frequency(for: "de") - 0.09) < 0.0001)
    #expect(abs(settings.frequency(for: "ru") - 0.21) < 0.0001)
    settings.enabledLanguages = ["de", "ru", "fr"]
    settings.languageFrequencies = ["de": 0.5, "ru": 0.5, "fr": 0.5]
    try settings.validate()
    #expect(abs(settings.effectiveFrequencies.values.reduce(0,+) - 0.5) < 0.0001)
    #expect(abs((settings.effectiveFrequencies["fr"] ?? 0) - 1.0/6) < 0.0001)
    #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)) == settings)
    settings.languageFrequencies = ["de":0, "ru":0, "fr":0]
    try settings.validate()
    #expect(settings.effectiveFrequencies.values.allSatisfy { $0 == 0 })
    settings.languageFrequencies["de"] = .nan
    #expect(throws: DomainError.self) { try settings.validate() }
}

private struct FixturePack: LanguagePack {
    let metadata: LanguagePackMetadata
    init(_ code: String) {
        metadata = LanguagePackMetadata(id: "test-"+code, languageCode: code, displayName: code,
            version: "test-only", schemaVersion: 1, lexiconDatabaseName: "none",
            supportedFeatures: [], licenseMetadata: ["purpose":"unit-test-fixture"])
    }
    func lookup(englishLemma lemma: String) async throws -> [LexicalEntry] {
        guard ["tea","coffee","and"].contains(lemma) else { return [] }
        let target: String
        switch (metadata.languageCode, lemma) {
        case ("de","tea"): target = "Tee"
        case ("de","coffee"): target = "Kaffee"
        case ("de","and"): target = "und"
        case (_,"tea"): target = "чай"
        case (_,"coffee"): target = "кофе"
        default: target = "и"
        }
        return [LexicalEntry(englishLemma: lemma, targetLemma: target, senseID: "test-"+lemma,
            partOfSpeech: lemma == "and" ? "conjunction" : "noun", contextExamples: [],
            morphologicalTags: ["definition": lemma == "and" ? "used to connect two similar words" : "a drink"],
            provenance: ["purpose":"unit-test-fixture"])]
    }
    func lookupSense(englishLemma: String, senseID: String) async throws -> LexicalEntry? { nil }
    func inflect(_ entry: LexicalEntry, features: [String:String]) async throws -> String? { entry.targetLemma }
    func validateReplacement(_ entry: LexicalEntry, surface: String, context: String) async throws -> Bool { true }
    func supportsPartOfSpeech(_ pos: String) -> Bool { true }
}

@Test func psychoAllocationMixedDeterministicAndReversible() async throws {
    let engine = ContextualReplacementEngine(registry: try LanguagePackRegistry(packs: [FixturePack("de"), FixturePack("ru")]))
    let original = "🌍 " + Array(repeating: "Tea and coffee, tea and coffee.", count: 10).joined(separator: " ")
    var settings = AppSettings()
    settings.languageFrequencies = ["de":0.5, "ru":0.5]
    let mix = try await engine.replace(text: original, sourceTextID: "stable", settings: settings, seed: 42)
    let repeated = try await engine.replace(text: original, sourceTextID: "stable", settings: settings, seed: 42)
    #expect(mix.spans == repeated.spans)
    #expect(mix.actualDensity >= 0.33)
    #expect(mix.actualDensity <= 0.5)
    #expect((mix.languageCounts["de"] ?? 0) > 0 && (mix.languageCounts["ru"] ?? 0) > 0)
    let passage = GeneratedText(id:"stable", originalEnglish:original, topic:"Test", cefrLevel:.b2,
        modelID:"fixture", seed:42, replacements:mix.spans)
    #expect(try passage.renderedText().hasPrefix("🌍 "))
    #expect(passage.originalEnglish == original)
    for pair in zip(mix.spans, mix.spans.dropFirst()) {
        #expect(pair.0.originalUTF16Range.location + pair.0.originalUTF16Range.length < pair.1.originalUTF16Range.location)
    }
    settings.languageFrequencies = ["de":0.1,"ru":0]
    let gentle = try await engine.replace(text:original, sourceTextID:"stable", settings:settings, seed:42)
    #expect(gentle.spans.count < mix.spans.count)
    #expect(gentle.spans.allSatisfy { $0.targetLanguageCode == "de" })
    settings.languageFrequencies = ["de":0,"ru":0]
    #expect(try await engine.replace(text:original,sourceTextID:"stable",settings:settings,seed:42).spans.isEmpty)
    settings.enabledLanguages = []
    #expect(try await engine.replace(text:original,sourceTextID:"stable",settings:settings,seed:42).spans.isEmpty)
}

@Test func realPacksContainSensesProvenanceAndRejectUnsupportedMorphology() async throws {
    for code in ["de","ru"] {
        let pack = try SQLiteLanguagePack(manifestURL: packDirectory.appendingPathComponent("en-\(code).json"))
        let bank = try await pack.lookup(englishLemma:"bank")
        #expect(bank.count > 3)
        #expect(bank.allSatisfy { $0.provenance["license"] == "CC-BY-SA-4.0" })
        #expect(Set(bank.map(\.senseID)).count > 3)
        let entry = try #require(bank.first)
        #expect(try await pack.inflect(entry,features:["requiresInflection":"true"]) == nil)
        #expect(try await pack.inflect(entry,features:["case":"dative"]) == nil)
        #expect(try await pack.lookup(englishLemma:"zzzznotaword").isEmpty)
    }
}

@Test func realSenseSelectionDistinguishesBanksAndSkipsAmbiguity() async throws {
    for code in ["de","ru"] {
        let pack = try SQLiteLanguagePack(manifestURL:packDirectory.appendingPathComponent("en-\(code).json"))
        let entries = try await pack.lookup(englishLemma:"bank")
        func token(_ sentence:String) -> EnglishToken {
            EnglishToken(surface:"bank",lemma:"bank",pos:"noun",span:.init(location:0,length:4),sentence:sentence,sentenceIndex:0)
        }
        let financial = SenseResolver.resolve(entries:entries, token:token("She deposited money at the bank."))
        let river = SenseResolver.resolve(entries:entries, token:token("The children played near the river bank."))
        #expect(financial != nil)
        #expect(river != nil)
        #expect(financial?.entry.targetLemma != river?.entry.targetLemma)
        #expect(SenseResolver.resolve(entries:entries, token:token("She noticed the bank.")) == nil)
        #expect(SenseResolver.resolve(entries:entries, token:token("The bank held money beside the river.")) == nil)
    }
}

@Test func enginePreservesUnsupportedVerbsAndMissingPacks() async throws {
    let engine = ContextualReplacementEngine(registry:try LanguagePackRegistry(directory:packDirectory))
    var settings = AppSettings(); settings.languageFrequencies = ["de":0.5,"ru":0.5]
    let mix = try await engine.replace(text:"The children charged forward. Banks closed. 🌍",sourceTextID:"id",settings:settings,seed:7)
    #expect(!mix.spans.contains { ["charged","closed"].contains($0.originalSurface) })
    let empty = ContextualReplacementEngine(registry:try LanguagePackRegistry(packs:[]))
    #expect(try await empty.replace(text:"Tea and coffee.",sourceTextID:"id",settings:settings,seed:7).spans.isEmpty)
}

@Test func remixUpdatesSessionWithoutDuplicatingOrChangingOriginal() async throws {
    var session = ReadingSession()
    let original = GeneratedText(id:"remix",originalEnglish:"Tea and coffee.",topic:"Test",cefrLevel:.b2,modelID:"fixture",seed:42)
    try session.append(original)
    let engine = ContextualReplacementEngine(registry:try LanguagePackRegistry(packs:[FixturePack("de")]))
    var settings = AppSettings(); settings.enabledLanguages = ["de"]; settings.languageFrequencies = ["de":0.5]
    let mix = try await engine.replace(text:original.originalEnglish,sourceTextID:original.id,settings:settings,seed:42)
    let remixed = GeneratedText(id:original.id,originalEnglish:original.originalEnglish,topic:original.topic,cefrLevel:original.cefrLevel,
        generatedAt:original.generatedAt,modelID:original.modelID,seed:original.seed,replacements:mix.spans)
    try session.remix(remixed)
    try session.remix(remixed)
    #expect(session.passages.count == 1)
    #expect(session.passages.first?.replacements == mix.spans)
    let changed = GeneratedText(id:original.id,originalEnglish:"Changed original.",topic:"Test",cefrLevel:.b2,modelID:"fixture",seed:42)
    #expect(throws:DomainError.self) { try session.remix(changed) }
    #expect(session.passages.first?.originalEnglish == original.originalEnglish)
}

@Test func tripDoesNotBecomeADrugExperienceInTravelContext() async throws {
    for code in ["de", "ru"] {
        let pack = try SQLiteLanguagePack(manifestURL:packDirectory.appendingPathComponent("en-\(code).json"))
        let entries = try await pack.lookup(englishLemma:"trip")
        func token(_ sentence:String) -> EnglishToken {
            EnglishToken(surface:"trip",lemma:"trip",pos:"noun",span:.init(location:0,length:4),sentence:sentence,sentenceIndex:0)
        }
        let travel = try #require(SenseResolver.resolve(entries:entries,
            token:token("My first meaningful trip was not just a destination, but an alchemy of experience.")))
        #expect(["Reise", "пое́здка"].contains(travel.entry.targetLemma))
        let drug = try #require(SenseResolver.resolve(entries:entries,
            token:token("The psychedelic drug caused a trip with vivid hallucinations.")))
        #expect(drug.entry.targetLemma != travel.entry.targetLemma)
        #expect(SenseResolver.resolve(entries:entries,token:token("A meaningful trip was an experience.")) == nil)
        #expect(SenseResolver.resolve(entries:entries,token:token("The travel journey involved a psychedelic drug trip.")) == nil)
    }
}

@Test func degreeAdverbsAndCompoundsUseTheActualLocalContext() async throws {
    let text = "A leather-bound notebook stood so high on a well‑known shelf. I often read it."
    let tokens = EnglishAnalyzer.tokens(in:text)
    let compoundParts = tokens.filter { ["leather", "bound", "well", "known"].contains($0.surface) }
    #expect(!compoundParts.isEmpty)
    #expect(compoundParts.allSatisfy { $0.isCompoundComponent })
    let so = try #require(tokens.first { $0.lemma == "so" })
    #expect(so.followingPOS == "adjective")
    for code in ["de","ru"] {
        let pack = try SQLiteLanguagePack(manifestURL:packDirectory.appendingPathComponent("en-\(code).json"))
        let resolved = try #require(SenseResolver.resolve(entries:try await pack.lookup(englishLemma:"so"),token:so))
        #expect(resolved.entry.morphologicalTags["definition"] == "to a particular extent")
    }
    let engine = ContextualReplacementEngine(registry:try LanguagePackRegistry(directory:packDirectory))
    var settings = AppSettings(); settings.languageFrequencies = ["de":0.5,"ru":0.5]
    let mix = try await engine.replace(text:text,sourceTextID:"compound",settings:settings,seed:3)
    #expect(!mix.spans.contains { ["leather","bound","well","known"].contains($0.originalSurface) })
}

@Test func functionWordPolicyChoosesExistingModernTranslations() async throws {
    let pack = try SQLiteLanguagePack(manifestURL:packDirectory.appendingPathComponent("en-ru.json"))
    let entry = try #require(try await pack.lookup(englishLemma:"or").first { $0.partOfSpeech == "conjunction" })
    #expect(entry.targetLemma == "и́ли")
    let alternatives = try JSONDecoder().decode([String].self,from:Data(try #require(entry.morphologicalTags["alternatives"]).utf8))
    #expect(alternatives.contains(entry.targetLemma))
    for code in ["de","ru"] {
        let pack = try SQLiteLanguagePack(manifestURL:packDirectory.appendingPathComponent("en-\(code).json"))
        for word in ["i","he","she","we"] {
            let token = EnglishToken(surface:word,lemma:word,pos:"pronoun",span:.init(location:0,length:word.utf16.count),sentence:"I read while she works.",sentenceIndex:0)
            #expect(SenseResolver.resolve(entries:try await pack.lookup(englishLemma:word),token:token) != nil)
        }
    }
}

@Test func aDistantKeywordDoesNotDisambiguateALocalWord() {
    let text = "She put money into an account at the bank, then slowly walked along the river bank to watch the water."
    let banks = EnglishAnalyzer.tokens(in:text).filter { $0.lemma == "bank" }
    #expect(banks.count == 2)
    #expect(banks[0].nearbyWords != banks[1].nearbyWords)
}

@Test func pronounLemmasNeverEraseObjectCaseOrReflexives() async throws {
    let text = "She taught me that I should help her. I found myself thinking while we rested."
    let engine = ContextualReplacementEngine(registry:try LanguagePackRegistry(directory:packDirectory))
    var settings = AppSettings(); settings.languageFrequencies = ["de":0.5,"ru":0.5]
    let mix = try await engine.replace(text:text,sourceTextID:"pronouns",settings:settings,seed:42)
    #expect(!mix.spans.contains { ["me","her","myself"].contains($0.originalSurface) })
    #expect(mix.spans.contains { ["She","I","we"].contains($0.originalSurface) })
    #expect(!mix.spans.contains { $0.originalSurface == $0.targetSurface })
    let tokens = EnglishAnalyzer.tokens(in:text)
    #expect(tokens.filter { $0.surface == "I" }.map(\.isSentenceInitial) == [false,true])
}

@Test func bundledEnglishTaggerMatchesKnownReferenceTokensWithoutAppleAssets() throws {
    let model = try BundledEnglishTagger(directory:packDirectory.appendingPathComponent("_english"))
    let words = ["The","quick","brown","fox","jumps","over","the","lazy","dog"]
    #expect(model.tags(for:words) == ["DT","JJ","NN","NN","VBZ","IN","DT","JJ","NN"])
    let text = "She taught me that I should read the book."
    let tokens = EnglishAnalyzer.tokens(in:text,bundledTagger:model)
    #expect(tokens.first { $0.surface == "She" }?.pos == "pronoun")
    #expect(tokens.first { $0.surface == "book" }?.pos == "noun")
    #expect(tokens.first { $0.surface == "read" }?.pos == "verb")
    #expect(tokens.allSatisfy { $0.pos != "unknown" })
    struct Fixture: Decodable { let tokens:[String]; let tags:[String] }
    struct Reference: Decodable { let fixtures:[Fixture] }
    let url = packDirectory.deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Tests/Fixtures/english-pos-reference.json")
    for fixture in try JSONDecoder().decode(Reference.self,from:Data(contentsOf:url)).fixtures {
        #expect(model.tags(for:fixture.tokens) == fixture.tags)
    }
}

@Test func oddLengthPsychoAndThreeLanguagesRespectTheSharedCeiling() async throws {
    let engine = ContextualReplacementEngine(registry:try LanguagePackRegistry(packs:[FixturePack("de"),FixturePack("ru"),FixturePack("fr")]))
    var settings = AppSettings();settings.enabledLanguages = ["de","ru","fr"]
    settings.languageFrequencies = ["de":0.5,"ru":0.5,"fr":0.5]
    let short = try await engine.replace(text:"Tea and coffee.",sourceTextID:"odd",settings:settings,seed:42)
    #expect(short.actualDensity <= 0.5)
    let original = Array(repeating:"Tea and coffee, tea and coffee.",count:10).joined(separator:" ")
    let mix = try await engine.replace(text:original,sourceTextID:"three",settings:settings,seed:42)
    #expect(mix.actualDensity <= 0.5 && mix.actualDensity >= 0.33)
    #expect(Set(mix.languageCounts.filter { $0.value > 0 }.keys) == ["de","ru","fr"])
    let tokens = EnglishAnalyzer.tokens(in:original)
    let locations = Set(mix.spans.map { $0.originalUTF16Range.location })
    for i in 0..<(tokens.count-2) {
        #expect(!tokens[i...i+2].allSatisfy { locations.contains($0.span.location) })
    }
}

@Test func spatialPrepositionsAndContentClausesUseTheirLocalHead() async throws {
    let registry = try LanguagePackRegistry(directory:packDirectory)
    let tokens = EnglishAnalyzer.tokens(in:"She stood before a tall oak tree in a quiet forest where she said that the notebook was on the table.",bundledTagger:registry.englishTagger)
    #expect(tokens.first { $0.lemma == "before" }?.followingNoun == "oak")
    #expect(tokens.first { $0.lemma == "in" }?.followingNoun == "forest")
    #expect(tokens.first { $0.lemma == "that" }?.pos == "conjunction")
    for pack in registry.packs {
        let before = try #require(tokens.first { $0.lemma == "before" })
        #expect(SenseResolver.resolve(entries:try await pack.lookup(englishLemma:"before"),token:before)?.entry.morphologicalTags["definition"] == "in front of in space")
        let topicTokens = EnglishAnalyzer.tokens(in:"She wrote notes on every possible route in a notebook.",bundledTagger:registry.englishTagger)
        let on = try #require(topicTokens.first { $0.lemma == "on" })
        #expect(on.followingNoun == "route")
        #expect(SenseResolver.resolve(entries:try await pack.lookup(englishLemma:"on"),token:on) == nil)
    }
}

@Test func boundMorphemesAndMisclassifiedFiniteVerbsStayInEnglish() async throws {
    let registry = try LanguagePackRegistry(directory:packDirectory)
    let pack = try SQLiteLanguagePack(manifestURL:packDirectory.appendingPathComponent("en-de.json"))
    let entry = try #require(try await pack.lookup(englishLemma:"most").first { $0.targetLemma == "-ste" })
    #expect(await pack.validateReplacement(entry,surface:"-ste",context:"the most profound departure") == false)
    let text = "She taught me that the most profound departure is not leaving a city, but choosing a path that honors your soul rather than merely following the crowd."
    let engine = ContextualReplacementEngine(registry:registry)
    var settings = AppSettings();settings.languageFrequencies = ["de":0.5,"ru":0.5]
    let mix = try await engine.replace(text:text,sourceTextID:"grammar",settings:settings,seed:42)
    #expect(!mix.spans.contains { ["most","honors"].contains($0.originalSurface) })
}

@Test func attestedPluralsAreUsedAndAmbiguousFormsAreSkipped() async throws {
    for (code, expected) in [("de","Karten"),("ru","карты")] {
        let pack = try SQLiteLanguagePack(manifestURL:packDirectory.appendingPathComponent("en-\(code).json"))
        let entry = try #require(try await pack.lookup(englishLemma:"map").first {
            ($0.morphologicalTags["definition"] ?? "").contains("visual representation")
        })
        #expect(try await pack.inflect(entry,features:["number":"plural"]) == expected)
        #expect(try await pack.inflect(entry,features:["number":"plural","case":"dative"]) == nil)
    }
    let german = try SQLiteLanguagePack(manifestURL:packDirectory.appendingPathComponent("en-de.json"))
    let bank = try #require(try await german.lookup(englishLemma:"bank").first { $0.targetLemma == "Bank" })
    #expect(try await german.inflect(bank,features:["number":"plural"]) == nil)
    let engine = ContextualReplacementEngine(registry:try LanguagePackRegistry(directory:packDirectory))
    var settings = AppSettings(); settings.languageFrequencies = ["de":0.5,"ru":0.5]
    let mix = try await engine.replace(text:"The notebook contains maps and handwritten notes for travel routes.",sourceTextID:"plural",settings:settings,seed:1)
    #expect(mix.spans.contains { $0.originalSurface == "maps" && ["Karten","карты"].contains($0.targetSurface) })
}
