import Foundation
import Testing
@testable import LinguaFrancaCore

private var packsURL: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/LanguagePacks") }

@Test func genreAndFocusPreferencesMigrateAndPersist() async throws {
    let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
    #expect(old.writingGenre == .story && old.replacementMode == .balanced)
    var settings = old; settings.writingGenre = .poem; settings.replacementMode = .aggressive; settings.practiceDomains = [.structure,.actions]
    #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)) == settings)
    let db = try DatabaseManager(); try await db.saveSettings(settings)
    #expect(try await db.settings() == settings)
    let prompts = WritingGenre.allCases.map { GenerationRequest(topic: "Education", seed: 42, genre: $0).prompt }
    #expect(Set(prompts).count == 6)
    for genre in WritingGenre.allCases { #expect(GenerationRequest(topic: "Education", seed: 42, genre: genre).prompt.contains(genre.instruction)) }
}

@Test func poemsAndSpeakerTurnsHaveFormatAwareValidation() throws {
    let line = "The quiet river carries every whispered promise beneath the morning sky"
    let poem = Array(repeating: line, count: 8).joined(separator: "\n")
    #expect(try PassageValidator.validate(poem, requestedWords: 110, genre: .poem) == poem)
    #expect(throws: GenerationError.self) { try PassageValidator.validate(poem, requestedWords: 110, genre: .story) }
    #expect(throws: GenerationError.self) { try PassageValidator.validate(poem.replacingOccurrences(of: "\n", with: " "), requestedWords: 110, genre: .poem) }
    let dialogue = (0..<8).map { "\($0.isMultiple(of: 2) ? "Maya" : "Ali"): We can repair the chair together before the visitor returns tonight." }.joined(separator: "\n")
    #expect(try PassageValidator.validate(dialogue, requestedWords: 110, genre: .dialogue) == dialogue)
    let play = "(They stand beside a broken chair.)\n" + dialogue
    #expect(try PassageValidator.validate(play, requestedWords: 110, genre: .play) == play)
    #expect(throws: GenerationError.self) { try PassageValidator.validate(dialogue, requestedWords: 110, genre: .play) }
    #expect(throws: GenerationError.self) { try PassageValidator.validate(poem + ".", requestedWords: 110, genre: .dialogue) }
}

@Test func focusedStructureMixesAllSafeMatchesAndRebalancesLanguages() async throws {
    let engine = ContextualReplacementEngine(registry: try LanguagePackRegistry(directory: packsURL))
    var settings = AppSettings(); settings.replacementMode = .aggressive; settings.practiceDomains = [.structure]
    settings.languageFrequencies = ["de":0.01,"ru":0.01]
    let result = try await engine.replace(text: "Tea and coffee and tea and coffee and tea and coffee.", sourceTextID: "structure", settings: settings, seed: 42)
    #expect(result.spans.count == 5)
    #expect(result.spans.allSatisfy { $0.originalPartOfSpeech == "conjunction" })
    #expect(Set(result.languageCounts.keys) == ["de","ru"])
    settings.practiceDomains = []
    #expect(try await engine.replace(text: "Tea and coffee.", sourceTextID: "none", settings: settings, seed: 42).spans.isEmpty)
}

@Test func focusedActionsUseRealInflectionsRatherThanCitationForms() async throws {
    for (code, present, converb) in [("de","lächelt","lächelnd"),("ru","улыбается","улыбаясь")] {
        let pack = try SQLiteLanguagePack(manifestURL: packsURL.appendingPathComponent("en-\(code).json"))
        let entry = try #require(try await pack.lookup(englishLemma: "smile").first { $0.partOfSpeech == "verb" })
        #expect(try await pack.inflect(entry, features: ["form":"finite","tense":"present","person":"3","number":"singular"]) == present)
        #expect(try await pack.inflect(entry, features: ["form":"converb"]) == converb)
        #expect(try await pack.inflect(entry, features: [:]) == nil)
        if code == "ru" {
            #expect(try await pack.inflect(entry, features: ["form":"finite","tense":"past","person":"3","number":"singular","gender":"feminine"]) == nil)
            #expect(try await pack.inflect(entry, features: ["form":"finite","tense":"past","number":"singular","gender":"feminine","habitual":"true"]) == "улыбалась")
        }
        var settings = AppSettings(); settings.enabledLanguages = [code]; settings.languageFrequencies = [code:0.01]
        settings.replacementMode = .aggressive; settings.practiceDomains = [.actions]
        let engine = ContextualReplacementEngine(registry: try LanguagePackRegistry(directory: packsURL))
        let result = try await engine.replace(text: "She smiles. He smiles. Smiling, she opened the door.", sourceTextID: code, settings: settings, seed: 42)
        #expect(result.spans.contains { $0.originalSurface == "smiles" && $0.targetSurface == present })
        #expect(result.spans.allSatisfy { $0.originalPartOfSpeech == "verb" })
    }
}

@Test func contentFocusIncludesSafePredicateAdjectives() async throws {
    var settings = AppSettings(); settings.enabledLanguages = ["ru"]; settings.languageFrequencies = ["ru":0.1]
    settings.replacementMode = .aggressive; settings.practiceDomains = [.content]
    let engine = ContextualReplacementEngine(registry: try LanguagePackRegistry(directory: packsURL))
    let result = try await engine.replace(text: "She is hungry before lunch and needs food. The children eat in the garden.", sourceTextID: "content", settings: settings, seed: 42)
    #expect(result.spans.contains { $0.originalSurface == "hungry" && $0.targetSurface == "голодна" })
    #expect(result.spans.allSatisfy { PracticeDomain.content.includes($0.originalPartOfSpeech) })
}

@Test func unknownVerbAgreementAndProgressivesAreSkipped() throws {
    let registry = try LanguagePackRegistry(directory: packsURL)
    let tokens = EnglishAnalyzer.tokens(in: "You smiled. She is smiling. She smiles. They smile.", bundledTagger: registry.englishTagger)
    #expect(tokens.first(where: { $0.surface == "smiled" }).flatMap(EnglishInflection.features) == nil)
    #expect(tokens.first(where: { $0.surface == "smiling" }).flatMap(EnglishInflection.features) == nil)
    #expect(tokens.first(where: { $0.surface == "smiles" }).flatMap(EnglishInflection.features)?["person"] == "3")
    #expect(tokens.first(where: { $0.surface == "smile" }).flatMap(EnglishInflection.features)?["number"] == "plural")
}

@Test func mixedSpeechKeepsSentenceBoundariesAndLanguageOrder() throws {
    let source = "Before dawn. 🌍 A decision followed the meeting. Later, everyone left."
    let id = "speech"
    var offset = 0
    let spans = [("decision","решение","ru"),("meeting","Besprechung","de")].map { original, target, language in
        let range = (source as NSString).range(of: original)
        let span = ReplacementSpan(sourceTextID: id, originalUTF16Range: .init(location: range.location, length: range.length),
            renderedUTF16Range: .init(location: range.location + offset, length: target.utf16.count), originalSurface: original,
            originalLemma: original, originalPartOfSpeech: "noun", sourceSenseID: "fixture", targetLanguageCode: language,
            targetLemma: target, targetSurface: target, translationConfidence: 0.9, languagePackVersion: "fixture")
        offset += target.utf16.count - range.length
        return span
    }
    let reading = GeneratedText(id: id, originalEnglish: source, topic: "Test", cefrLevel: .c1, modelID: "fixture", seed: 42, replacements: spans)
    let selected = try #require(spans.first)
    let segments = try reading.speechSegments(for: selected)
    let context = try reading.vocabularyContext(for: selected)
    #expect(segments.map(\.languageCode) == ["en","ru","en","de"])
    #expect(segments.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines) == context.mixed)
    let english = try reading.speechSegments(for: selected, original: true)
    #expect(english.count == 1 && english[0].languageCode == "en")
    #expect(!english[0].text.contains("Before") && !english[0].text.contains("Later"))
}

@Test func focusGroupsCanBeCombinedWithoutSelectingContentWords() async throws {
    var settings = AppSettings(); settings.replacementMode = .aggressive; settings.practiceDomains = [.structure,.actions]
    let engine = ContextualReplacementEngine(registry: try LanguagePackRegistry(directory: packsURL))
    let result = try await engine.replace(text: "She smiles and he smiles.", sourceTextID: "combination", settings: settings, seed: 42)
    #expect(Set(result.spans.map(\.originalPartOfSpeech)) == ["verb","conjunction"])
    #expect(result.spans.count == 3)
}

@Test func poemSpeechReadsOnlyTheSelectedLine() throws {
    let source = "A river carries light\nA decision waits beneath the stars\nThe garden sleeps"
    let range = (source as NSString).range(of: "decision"), id = "poem-line"
    let span = ReplacementSpan(sourceTextID: id, originalUTF16Range: .init(location: range.location,length: range.length),
        renderedUTF16Range: .init(location: range.location,length: "решение".utf16.count), originalSurface: "decision", originalLemma: "decision",
        originalPartOfSpeech: "noun", sourceSenseID: "fixture", targetLanguageCode: "ru", targetLemma: "решение", targetSurface: "решение",
        translationConfidence: 0.9, languagePackVersion: "fixture")
    let reading = GeneratedText(id: id, originalEnglish: source, topic: "Test", cefrLevel: .c1, modelID: "fixture", seed: 42,
        metadata: ["writingGenre":"poem"], replacements: [span])
    #expect(try reading.vocabularyContext(for: span).english == "A decision waits beneath the stars")
    #expect(try reading.speechSegments(for: span).map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines) == "A решение waits beneath the stars")
}

@Test func nichijouIsEverydayEnglishAndPersistsWithoutChangingCEFRReadings() async throws {
    var settings = AppSettings(); settings.generationLevel = .nichijou; settings.generationTopic = "Daily life"
    let db = try DatabaseManager(); try await db.saveSettings(settings)
    #expect(try await db.settings() == settings)
    #expect(try JSONDecoder().decode(CEFRLevel.self, from: Data("\"C1\"".utf8)) == .c1)
    for genre in WritingGenre.allCases {
        let request = GenerationRequest(topic: "Daily life", level: .nichijou, seed: 45, genre: genre)
        #expect(request.prompt.contains("everyday English"))
        #expect(!request.prompt.contains("CEFR Nichijou"))
        var aggressive = request; settings.replacementMode = .aggressive
        aggressive.aggressiveTask = try AggressiveModelTask(settings: settings)
        #expect(aggressive.prompt.contains("everyday English"))
        if [.dialogue, .play, .poem].contains(genre) {
            #expect(aggressive.outputGrammar!.contains(#""\"english\":" ws english"#))
            #expect(aggressive.outputGrammar!.contains(#""\\n""#))
        }
    }
}

@Test func conversationalShortTurnsAndPunctuationSurviveValidation() throws {
    let text = "Alex: Hey, is this seat taken?\nSam: No, go ahead!\nAlex: Thanks. I'm waiting for the 8:30 bus.\nSam: Me too. Is it usually this late?\nAlex: Only when it rains. Want some coffee?\nSam: I'd love some, thanks!"
    #expect(try PassageValidator.validate(text, requestedWords: 110, genre: .dialogue) == text)
    #expect(throws: GenerationError.self) { try PassageValidator.validate("Alex: Hello!\nSam: Hi!", requestedWords: 110, genre: .dialogue) }
    let repeated = Array(repeating: "Alex: Hello!", count: 6).joined(separator: "\n")
    #expect(throws: GenerationError.self) { try PassageValidator.validate(repeated, requestedWords: 110, genre: .dialogue) }
}

@Test func embeddedSpeakerChangesAreNotAcceptedAsCleanDialogue() throws {
    let text = "Alex: Hello! Sam: Hello there!\nSam: How are you?\nAlex: Fine, thanks!\nSam: Want a coffee?\nAlex: Yes, please!\nSam: Here you go!"
    #expect(throws: GenerationError.self) { try PassageValidator.validate(text, requestedWords: 110, genre: .dialogue) }
}
