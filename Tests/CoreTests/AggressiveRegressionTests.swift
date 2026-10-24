import Foundation
import Testing
@testable import LinguaFrancaCore

private var packs: URL { URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/LanguagePacks") }

@Test func aggressiveCommonGrammarHasNoUntranslatedSelectedTokens() async throws {
    let engine = ContextualReplacementEngine(registry:try LanguagePackRegistry(directory:packs))
    let cases: [(String, Set<PracticeDomain>)] = [
        ("After lunch she smiles because he smiles before dinner.",[.structure]),
        ("When he writes in the room, she reads with a child.",[.structure]),
        ("She can smile and he can laugh.",[.structure,.actions]),
        ("He was smiling while she was laughing.",[.structure,.actions]),
        ("She smiled yesterday and he laughed.",[.actions]),
        ("The roof of the house near the kitchen window is old.",[.structure]),
        ("She works and he writes. They read and we smile.",[.actions]),
        ("She does not smile and he is smiling.",[.structure,.actions])
    ]
    for code in ["de","ru"] {
        for (text,domains) in cases {
            var settings = AppSettings(); settings.replacementMode = .aggressive; settings.practiceDomains = domains
            settings.enabledLanguages = [code]; settings.languageFrequencies = [code:0]
            let result = try await engine.replace(text:text,sourceTextID:"regression",settings:settings,seed:42)
            print("COVERAGE \(code) \(text) => \(result.replacedWordCount)/\(result.eligibleWordCount); missing=\(result.unresolved.map(\.surface))")
            #expect(result.unresolved.isEmpty, "\(code): \(text); missing \(result.unresolved.map(\.surface))")
            let reading = GeneratedText(id:"regression",originalEnglish:text,topic:"Test",cefrLevel:.b2,modelID:"fixture",seed:42,replacements:result.spans)
            _ = try reading.renderedText()
        }
    }
}

@Test func wordPronunciationContainsOnlyTheTargetExpression() {
    let span = ReplacementSpan(sourceTextID:"voice",originalUTF16Range:.init(location:0,length:5),renderedUTF16Range:.init(location:0,length:9),originalSurface:"smile",originalLemma:"smile",originalPartOfSpeech:"verb",sourceSenseID:"test",targetLanguageCode:"ru",targetLemma:"улыбаться",targetSurface:"улыбается",translationConfidence:1,languagePackVersion:"test")
    #expect(span.pronunciation.text == "улыбается")
    #expect(span.pronunciation.languageCode == "ru")
}

@Test func validGeneratedTextIsNotRejectedByLengthAndKeepsCompletedSentences() throws {
    let sentence = "She walks through the garden and watches the children near the door."
    #expect(try PassageValidator.validate(sentence,requestedWords:110) == sentence)
    let long = Array(repeating:sentence,count:20).joined(separator:" ")
    #expect(try PassageValidator.validate(long,requestedWords:90) == long)
    #expect(try PassageValidator.validate(sentence + " Then she starts to",requestedWords:110) == sentence)
    #expect(try PassageValidator.validate("```text\n" + sentence + "\n```",requestedWords:110) == sentence)
    #expect(try PassageValidator.validate("Here is your passage:\n" + sentence,requestedWords:110) == sentence)
}

@Test func intermediateEnglishRemainsVisibleAndOneGenerateActionHasOneCard() throws {
    var session = ReadingSession()
    let first = GeneratedText(id:"draft",originalEnglish:"She smiles and he reads.",topic:"Test",cefrLevel:.b2,modelID:"fixture",seed:1,metadata:["generationGroupID":"action","replacementComplete":"false"])
    try session.append(first)
    #expect(session.visiblePassages.first?.originalEnglish == first.originalEnglish)
    let next = GeneratedText(id:"ready",originalEnglish:"They write a letter beside the open window.",topic:"Test",cefrLevel:.b2,modelID:"fixture",seed:2,metadata:["generationGroupID":"action","replacementComplete":"true"])
    try session.append(next)
    #expect(session.visiblePassages.count == 1 && session.visiblePassages.first?.id == "ready")
    #expect(session.passages.contains { $0.id == "draft" })
}

@Test func checkedTranslationsPreserveMeaningAndInflection() async throws {
    let engine = ContextualReplacementEngine(registry:try LanguagePackRegistry(directory:packs))
    for (code, expected) in [("de",["kann","lächeln","schreibt","lächelte"]),("ru",["может","улыбаться","пишет","улыбался"])] {
        var settings = AppSettings(); settings.enabledLanguages = [code]; settings.replacementMode = .aggressive; settings.practiceDomains = [.actions]
        let result = try await engine.replace(text:"She can smile. He writes. He was smiling.",sourceTextID:code,settings:settings,seed:42)
        #expect(result.unresolved.isEmpty)
        for word in expected { #expect(result.spans.contains { $0.targetSurface == word }) }
        #expect(!result.spans.contains { $0.targetSurface == "писает" })
    }
}

private actor DictionarySelectionProbe: ContextualSenseSelecting {
    private(set) var requests: [ContextualSenseRequest] = []
    let invalidIndex: Bool
    init(invalidIndex:Bool = false) { self.invalidIndex = invalidIndex }
    func selectSense(_ request: ContextualSenseRequest) async throws -> Int? {
        requests.append(request)
        if invalidIndex { return 99 }
        return request.options.firstIndex { $0.definition.localizedCaseInsensitiveContains("financial") || $0.definition.localizedCaseInsensitiveContains("institution") }
    }
}

@Test func semanticSelectionCanOnlyRenderAnExistingVerifiedDictionaryChoice() async throws {
    let registry = try LanguagePackRegistry(directory:packs), selector = DictionarySelectionProbe()
    var settings = AppSettings(); settings.replacementMode = .aggressive; settings.practiceDomains = [.content]; settings.enabledLanguages = ["de"]
    let engine = ContextualReplacementEngine(registry:registry,senseSelector:selector)
    let text = "The bank beside the river approved a loan."
    let result = try await engine.replace(text:text,sourceTextID:"sense",settings:settings,seed:42)
    #expect(result.spans.contains { $0.originalSurface == "bank" && $0.targetSurface == "Bank" })
    #expect(await selector.requests.contains { $0.expression == "bank" && $0.sentence.contains("[[bank]]") })
    let invalid = ContextualReplacementEngine(registry:registry,senseSelector:DictionarySelectionProbe(invalidIndex:true))
    let rejected = try await invalid.replace(text:text,sourceTextID:"invalid",settings:settings,seed:42)
    #expect(rejected.unresolved.contains { $0.surface == "bank" })
    let request = ContextualSenseRequest(expression:"bank",partOfSpeech:"noun",sentence:"A bank approved a loan.",languageCode:"de",options:[.init(definition:"financial institution",target:"Bank")])
    #expect(try request.selection("1") == 0)
    #expect(try request.selection("0") == nil)
    #expect(throws:GenerationError.self) { try request.selection("A fabricated translation") }
}

@Test func indirectQuestionsAndConditionalClausesUseDifferentConstructions() async throws {
    let engine = ContextualReplacementEngine(registry:try LanguagePackRegistry(directory:packs))
    for (code,question,condition) in [("de","ob sie lächelt","Wenn"),("ru","улыбается ли она","Если")] {
        var settings = AppSettings(); settings.replacementMode = .aggressive; settings.practiceDomains = [.structure]; settings.enabledLanguages = [code]
        let indirect = try await engine.replace(text:"He asked if she smiles.",sourceTextID:"question",settings:settings,seed:42)
        #expect(indirect.unresolved.isEmpty)
        #expect(indirect.spans.contains { $0.originalSurface == "if she smiles" && $0.targetSurface == question })
        let conditional = try await engine.replace(text:"If she asks, he smiles.",sourceTextID:"condition",settings:settings,seed:42)
        #expect(conditional.spans.contains { $0.originalSurface == "If" && $0.targetSurface == condition })
    }
}

@Test func spatialPrepositionsNeverUseUnrelatedTemporalOrTopicMeanings() async throws {
    let engine = ContextualReplacementEngine(registry:try LanguagePackRegistry(directory:packs))
    for (code,expected) in [("de",["hinter","um","zu"]),("ru",["за","вокруг","к"])] {
        var settings = AppSettings(); settings.replacementMode = .aggressive; settings.practiceDomains = [.structure]; settings.enabledLanguages = [code]
        let result = try await engine.replace(text:"She stands behind the train, walks around the house, and runs toward the city.",sourceTextID:"spatial",settings:settings,seed:42)
        for (source,target) in zip(["behind","around","toward"],expected) {
            #expect(result.spans.contains { $0.originalSurface == source && $0.targetSurface.replacingOccurrences(of:"\u{301}",with:"") == target },"\(code) \(source): \(result.spans.map { $0.originalSurface+"="+$0.targetSurface })")
        }
    }
}

@Test func aggressivePromptPrioritizesSelectedProfilesWithoutAWordCountLimit() {
    let request = GenerationRequest(topic:"Daily life",seed:42,aggressiveDomains:[.structure,.actions,.content,.prepositionalPhrases])
    let system = request.chatPrompt.components(separatedBy:"<|im_end|>").first ?? ""
    #expect(system.contains("simple PRESENT"))
    #expect(system.contains("MANY conjunctions"))
    #expect(system.contains("MANY concrete nouns"))
    #expect(system.contains("several distinct concrete actions"))
    #expect(system.contains("MANY complete preposition"))
    #expect(!request.prompt.contains("110 words"))
    let sense = ContextualSenseRequest(expression:"move in",partOfSpeech:"expression",sentence:"They [[move in]] unison.",languageCode:"ru",options:[.init(definition:"start residing at a place",target:"вселяться")])
    #expect(!sense.prompt.contains("вселяться"))
    #expect(sense.prompt.contains("literal non-idiomatic"))
}
