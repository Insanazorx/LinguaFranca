import Foundation
import Testing
@testable import LinguaFrancaCore

@Test func aggressiveAssignmentsMigrateAndBalancedPromptStaysEnglish() throws {
    var settings=AppSettings();settings.replacementMode = .aggressive
    settings.aggressiveLanguageAssignments=["structure":"de","actions":"ru"]
    let task=try AggressiveModelTask(settings:settings)
    #expect(task.assignments["structure"] == "de" && task.assignments["actions"] == "ru")
    let plain=GenerationRequest(topic:"Garden",seed:1)
    #expect(!plain.prompt.contains("Output JSON"))
    #expect(plain.aggressiveTask == nil && plain.configuration.maximumTokens == 320)
    settings.enabledLanguages=["de"]
    #expect(settings.aggressiveLanguage(for:.actions) == "auto")
    settings.enabledLanguages=["syc"]
    #expect(try AggressiveModelTask(settings:settings).languages == ["syc"])
}

@Test func aggressiveModelCoversRepeatedOccurrencesWithUnicodeRoundTrip() throws {
    var settings=AppSettings();settings.replacementMode = .aggressive;settings.practiceDomains=[.structure];settings.enabledLanguages=["de"]
    let task=try AggressiveModelTask(settings:settings),validator=AggressiveCoverageValidator()
    let english="📚 She reads and he smiles, and they sit near the garden."
    let slots=validator.slots(english:english,task:task)
    #expect(slots.filter { $0.source == "and" }.count == 2)
    #expect(slots.contains { $0.source == "near" })
    let targets=slots.map { $0.source == "and" ? "und" : "neben" }
    let result=GenerationResult(englishText:english,duration:1,modelIdentifier:"2B",seed:1,tokenCount:50,metadata:[:])
    let reading=try validator.reading(english:english,slots:slots,targets:targets,request:.init(topic:"Garden",seed:1),result:result)
    #expect(try reading.renderedText() == "📚 She reads und he smiles, und they sit neben the garden.")
    #expect(reading.originalEnglish == english)
    #expect(throws:GenerationError.self) { try validator.reading(english:english,slots:slots,targets:["und"],request:.init(topic:"Garden",seed:1),result:result) }
    let draft=try AggressiveDraft.decode(#"{"english":"candy and tea and cake.","replacements":[{"source":"and","target":"und","language":"de","occurrence":1}]}"#)
    let map=validator.targets(draft,task:task)
    #expect(map.count == 1 && map.keys.first?.location == 14)
}

@Test func aggressivePhraseSlotsAreAtomicAndDoNotOverlap() throws {
    var settings=AppSettings();settings.replacementMode = .aggressive;settings.practiceDomains=[.structure,.prepositionalPhrases,.actions];settings.enabledLanguages=["de"]
    let slots=AggressiveCoverageValidator().slots(english:"She walks into the garden and sits near the house.",task:try .init(settings:settings))
    #expect(slots.contains { $0.source == "into the garden" })
    for pair in zip(slots,slots.dropFirst()) { #expect(pair.0.range.location+pair.0.range.length <= pair.1.range.location) }
    #expect(!AggressiveCoverageValidator.validTarget("and",slot:.init(source:"and",range:.init(location:0,length:3),language:"ru",partOfSpeech:"conjunction")))
}

@Test func truncatedMappingsRetainOnlyACompleteEnglishSource() throws {
    let partial = #"{"english":"She smiles and waves.","replacements":[{"source":"and""#
    let result=try AggressiveDraft.decodeRetainingSource(partial)
    #expect(result.english == "She smiles and waves." && result.replacements.isEmpty)
    #expect(throws:GenerationError.self) { try AggressiveDraft.decodeRetainingSource(#"{"english":"She smiles"#) }
}

@Test func aggressiveOnlyCorrectsFiniteClausesAndKeepsWholeVerbAndNounGroups() throws {
    var settings=AppSettings();settings.replacementMode = .aggressive;settings.enabledLanguages=["de"];settings.practiceDomains=[.structure,.actions,.prepositionalPhrases]
    let validator=AggressiveCoverageValidator(),task=try AggressiveModelTask(settings:settings)
    let slots=validator.slots(english:"She did not smile near the garden gate until the sun disappeared.",task:task)
    #expect(slots.contains { $0.source == "did not smile" })
    #expect(slots.contains { $0.source == "near the garden gate" })
    #expect(slots.contains { $0.source == "until" && $0.partOfSpeech == "conjunction" })
    #expect(!slots.contains { $0.source == "until the sun" })
}

private actor PairedModelFixture:TextGenerationService {
    var calls=0
    let cancelRepair:Bool
    init(cancelRepair:Bool=false) { self.cancelRepair=cancelRepair }
    func loadModel() {}
    func unloadModel() {}
    func cancelGeneration() {}
    func generate(request:GenerationRequest) async throws -> GenerationResult {
        calls += 1
        let task=try #require(request.aggressiveTask)
        let text:String
        if let repair=task.repair {
            if cancelRepair { throw CancellationError() }
            let values=repair.slots.map { ["source":$0.source,"target":$0.source == "works" ? "arbeitet" : "schreibt"] }
            text=String(decoding:try JSONEncoder().encode(values),as:UTF8.self)
        } else {
            text = #"{"english":"He works and she writes before breakfast.","replacements":[{"source":"and","target":"und","language":"de","occurrence":0}]}"#
        }
        return .init(englishText:text,duration:1,modelIdentifier:"fixture-2B",seed:request.seed,tokenCount:10,metadata:[:])
    }
}
private actor SourceObserver {
    var texts:[GeneratedText]=[]
    func append(_ source:GeneratedText) { texts.append(source) }
}
@Test func pairedModelRepairsMissingOccurrencesAndPreservesSourceOnCancellation() async throws {
    let folder=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/LanguagePacks")
    let registry=try LanguagePackRegistry(directory:folder)
    var settings=AppSettings();settings.replacementMode = .aggressive;settings.practiceDomains=[.actions];settings.enabledLanguages=["de"]
    let model=PairedModelFixture(),observer=SourceObserver(),request=GenerationRequest(topic:"Morning",seed:7)
    let reading=try await AggressiveReadingGenerator(model:model,registry:registry).generate(request:request,settings:settings) { await observer.append($0) }
    #expect(try reading.renderedText() == "He arbeitet and she schreibt before breakfast.")
    #expect(reading.metadata["repairedOccurrences"] == "2")
    #expect(await model.calls == 2)
    #expect(await observer.texts.count == 1)
    let cancelled=PairedModelFixture(cancelRepair:true),cancelledObserver=SourceObserver()
    await #expect(throws:CancellationError.self) {
        try await AggressiveReadingGenerator(model:cancelled,registry:registry).generate(request:request,settings:settings) { await cancelledObserver.append($0) }
    }
    #expect(await cancelledObserver.texts.count == 1)
}

@Test func everyPairAndTripleOfTheFiveLanguagesCanShareOneReading() async throws {
    let folder=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/LanguagePacks")
    let registry=try LanguagePackRegistry(directory:folder),validator=AggressiveCoverageValidator(registry:registry)
    let codes=["de","ru","ar","he","syc"],text=Array(repeating:"She writes and he waits.",count:9).joined(separator:" ")
    var combinations:[[String]]=[]
    for a in codes.indices { for b in codes.indices where b > a {
        combinations.append([codes[a],codes[b]])
        for c in codes.indices where c > b { combinations.append([codes[a],codes[b],codes[c]]) }
    } }
    for languages in combinations {
        var settings=AppSettings();settings.replacementMode = .aggressive;settings.practiceDomains=[.structure];settings.enabledLanguages=languages
        let task=try AggressiveModelTask(settings:settings),slots=try await validator.preparedSlots(english:text,task:task)
        #expect(Set(slots.map(\.language)) == Set(languages))
        let targets=slots.map { slot in
            slot.attestedOptions.first?.surface ?? ["de":"und","ru":"и","ar":"و","he":"ו"][slot.language]!
        }
        let output=try validator.reading(english:text,slots:slots,targets:targets,request:.init(topic:"Words",seed:5),result:.init(englishText:text,duration:0,modelIdentifier:"fixture",seed:5,tokenCount:1,metadata:[:]))
        #expect(Set(output.replacements.map(\.targetLanguageCode)) == Set(languages))
        #expect(try !output.renderedText().isEmpty)
        for span in output.replacements where span.targetLanguageCode == "syc" { #expect(span.lexicalReference?.lexemeID != nil) }
    }
    #expect(combinations.count == 20)
}

private actor TripleModelFixture:TextGenerationService {
    func loadModel() {}
    func unloadModel() {}
    func cancelGeneration() {}
    func generate(request:GenerationRequest) throws -> GenerationResult {
        try request.validate()
        let text:String
        if let repair=request.aggressiveTask?.repair {
            let targets=repair.slots.map { slot in ["source":slot.source,"target":slot.attestedOptions.first?.surface ?? (slot.language == "ar" ? "و" : "ו")] }
            text=String(decoding:try JSONEncoder().encode(targets),as:UTF8.self)
        } else {
            text = #"{"english":"She writes and he waits and she rests and he smiles and they leave.","replacements":[]}"#
        }
        return .init(englishText:text,duration:0,modelIdentifier:"fixture-2B",seed:request.seed,tokenCount:1,metadata:[:])
    }
}
@Test func semiticTripleOrchestrationKeepsSourceHintsAndCorpusMappingsValid() async throws {
    let folder=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/LanguagePacks")
    let registry=try LanguagePackRegistry(directory:folder)
    var settings=AppSettings();settings.replacementMode = .aggressive;settings.practiceDomains=[.structure];settings.enabledLanguages=["ar","he","syc"]
    let reading=try await AggressiveReadingGenerator(model:TripleModelFixture(),registry:registry).generate(request:.init(topic:"Work",seed:1),settings:settings)
    #expect(Set(reading.replacements.map(\.targetLanguageCode)) == ["ar","he","syc"])
    #expect(reading.metadata["unrepresentedLanguages"] == "")
    #expect(try reading.renderedText().contains("ܘ"))
}
