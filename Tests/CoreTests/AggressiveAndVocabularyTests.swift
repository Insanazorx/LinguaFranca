import Foundation
import Testing
@testable import LinguaFrancaCore

private var languageDirectory: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/LanguagePacks") }

@Test func aggressiveMigratesAndIgnoresBalancedFrequencies() async throws {
    let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"replacementMode":"focused","languageFrequencies":{"de":0,"ru":0}}"#.utf8))
    #expect(old.replacementMode == .aggressive)
    var settings = old; settings.practiceDomains = [.structure]
    let engine = ContextualReplacementEngine(registry: try LanguagePackRegistry(directory: languageDirectory))
    let zero = try await engine.replace(text: "Tea and coffee and tea and coffee and tea and coffee.", sourceTextID: "all", settings: settings, seed: 42)
    settings.languageFrequencies = ["de":0.5,"ru":0.01]
    let changed = try await engine.replace(text: "Tea and coffee and tea and coffee and tea and coffee.", sourceTextID: "all", settings: settings, seed: 42)
    #expect(zero.spans.count == 5 && changed.spans == zero.spans)
    #expect(Set(zero.languageCounts.keys) == ["de","ru"])
}

@Test func casePhrasesUseAttestedNounsAndGermanArticles() async throws {
    for code in ["de","ru"] {
        let pack = try SQLiteLanguagePack(manifestURL: languageDirectory.appendingPathComponent("en-\(code).json"))
        let house = try #require(try await pack.lookup(englishLemma: "house").first { $0.partOfSpeech == "noun" && ($0.morphologicalTags["definition"] ?? "").isEmpty })
        #expect(try await pack.nounPhrase(house, number: "singular", grammaticalCase: code == "de" ? "dative" : "prepositional", article: "the") == (code == "de" ? "dem Haus" : "доме"))
        #expect(try await pack.nounPhrase(house, number: "plural", grammaticalCase: "dative", article: "the") == (code == "de" ? "den Häusern" : "домам"))
        if code == "ru" {
            let forest = try #require(try await pack.lookup(englishLemma: "forest").first { $0.partOfSpeech == "noun" && $0.targetLemma == "лес" })
            #expect(try await pack.nounPhrase(forest, number: "singular", grammaticalCase: "prepositional", article: "the") == "лесу")
        }
    }
}

@Test func phrasePracticeIsAtomicReversibleAndDistinguishesMotion() async throws {
    let engine = ContextualReplacementEngine(registry: try LanguagePackRegistry(directory: languageDirectory))
    let source = "🌍 She sits in the house near the kitchen window. She walks into the house through the door."
    for code in ["de","ru"] {
        var settings = AppSettings(); settings.enabledLanguages = [code]; settings.replacementMode = .aggressive
        settings.practiceDomains = [.prepositionalPhrases,.structure,.content]
        let mixed = try await engine.replace(text: source, sourceTextID: code, settings: settings, seed: 42)
        let location = try #require(mixed.spans.first { $0.originalSurface == "in the house" })
        let motion = try #require(mixed.spans.first { $0.originalSurface == "into the house" })
        #expect(location.targetSurface == (code == "de" ? "in dem Haus" : "в доме"))
        #expect(motion.targetSurface == (code == "de" ? "in das Haus" : "в дом"))
        let reading = GeneratedText(id: code, originalEnglish: source, topic: "Test", cefrLevel: .b2, modelID: "fixture", seed: 42, replacements: mixed.spans)
        #expect(try reading.renderedText().contains(location.targetSurface))
        #expect(try reading.speechSegments(for: location).contains { $0.text.contains(location.targetSurface) && $0.languageCode == code })
        for pair in zip(mixed.spans,mixed.spans.dropFirst()) { #expect(pair.0.originalUTF16Range.location + pair.0.originalUTF16Range.length <= pair.1.originalUTF16Range.location) }
        #expect(mixed.replacedWordCount > mixed.spans.count)
    }
}

@Test func nonfinitePrepositionPracticeUsesCorrectTargetConstruction() async throws {
    let engine = ContextualReplacementEngine(registry: try LanguagePackRegistry(directory: languageDirectory))
    for code in ["de","ru"] {
        var settings = AppSettings(); settings.enabledLanguages = [code]; settings.replacementMode = .aggressive; settings.practiceDomains = [.prepositionalPhrases]
        let mixed = try await engine.replace(text: "She left without smiling.", sourceTextID: code, settings: settings, seed: 42)
        #expect(mixed.spans.first { $0.originalSurface == "without smiling" }?.targetSurface == (code == "de" ? "ohne zu lächeln" : "не улыбаясь"))
        let unknown = try await engine.replace(text: "She moved in the house near the kitchen. She left with the strange old friend.", sourceTextID: code, settings: settings, seed: 42)
        #expect(!unknown.spans.contains { $0.originalSurface.contains("in the house") || $0.originalSurface.contains("old friend") })
    }
}

@Test func conditionalAndInterrogativeIfAreNotConfused() async throws {
    let engine = ContextualReplacementEngine(registry: try LanguagePackRegistry(directory: languageDirectory))
    var settings = AppSettings(); settings.replacementMode = .aggressive; settings.practiceDomains = [.structure]
    let conditional = try await engine.replace(text: "If she smiles, he smiles too.", sourceTextID: "if", settings: settings, seed: 1)
    #expect(conditional.spans.contains { $0.originalSurface == "If" })
    let indirect = try await engine.replace(text: "He asked if she smiles.", sourceTextID: "whether", settings: settings, seed: 1)
    #expect(!indirect.spans.contains { $0.originalSurface == "if" })
}

@Test func relativeThatAndUnsupportedWholePhrasesNeverBecomeStandaloneFunctionWords() async throws {
    let engine = ContextualReplacementEngine(registry: try LanguagePackRegistry(directory: languageDirectory))
    var settings = AppSettings(); settings.replacementMode = .aggressive; settings.practiceDomains = [.structure]
    let text = "I believe that she smiles. The chair that supports the child is old."
    let mixed = try await engine.replace(text: text, sourceTextID: "that", settings: settings, seed: 42)
    #expect(mixed.spans.filter { $0.originalSurface == "that" }.count == 1)
    #expect(mixed.spans.first { $0.originalSurface == "that" }?.originalUTF16Range.location == (text as NSString).range(of:"that").location)
    settings.practiceDomains.insert(.prepositionalPhrases)
    let unsupported = try await engine.replace(text: "She walks with two children.", sourceTextID:"quantity",settings:settings,seed:42)
    #expect(unsupported.spans.contains { $0.originalSurface == "with" })
    settings.practiceDomains = [.prepositionalPhrases]
    let phraseOnly = try await engine.replace(text: "She walks with two children.",sourceTextID:"phrase-only",settings:settings,seed:42)
    #expect(!phraseOnly.spans.contains { $0.originalSurface == "with" })
}

private func item(_ id: String, _ code: String, _ target: String) -> VocabularyItem {
    .init(id: id, draft: .init(englishLemma: "word", targetLanguage: code, targetLemma: target, targetSurface: target, senseID: "meaning"), createdAt: .now)
}

@Test func vocabularyGroupingAndBatchingKeepEveryWordInItsOwnLanguage() throws {
    let words = (0..<14).map { item(String(format:"%02d",$0),"de","Wort\($0)") } + [item("ru","ru","слово")]
    let groups = VocabularyLanguageGroup.grouped(words)
    #expect(groups.map(\.languageCode) == ["de","ru"])
    let batches = try VocabularyPracticeRequest.batches(items: groups[0].items, languageCode: "de")
    #expect(batches.map { $0.expressions.count } == [3,3,3,3,2])
    #expect(Set(batches.flatMap { $0.expressions.map(\.id) }).count == 14)
    #expect(throws: DomainError.self) { try VocabularyPracticeRequest.batches(items: words, languageCode: "de") }
    let request = GenerationRequest(topic: "Practice", seed: 42, genre: .dialogue, vocabularyPractice: batches[0])
    #expect(request.outputGrammar == nil)
    #expect(request.chatPrompt.contains("ausschließlich auf Deutsch") && !request.prompt.contains("Write in English"))
}

@Test func vocabularyTextsRequireTargetLanguageAndEveryWholeExpression() throws {
    let de = VocabularyPracticeRequest(languageCode: "de", expressions: [.init(id:"1",target:"Garten",english:"garden",meaning:"outdoor plants")])
    let german = "Am Morgen gehe ich in den Garten und sehe die Blumen. Meine Schwester kommt mit einem Buch und wir sitzen gemeinsam unter dem alten Baum. Dort verbringen wir einen ruhigen Tag."
    #expect(try VocabularyPracticeValidator.validate(german, request: de) == german)
    let longText = Array(repeating: german, count: 6).joined(separator: " ")
    #expect(try VocabularyPracticeValidator.validate(longText, request: de) == longText)
    let shortText = "Im Garten wachsen heute viele bunte Blumen unter alten Bäumen."
    #expect(try VocabularyPracticeValidator.validate(shortText, request: de) == shortText)
    #expect(try VocabularyPracticeValidator.validate(german + " Ein unvollständiger letzter Satz", request: de) == german)
    #expect(throws: GenerationError.self) { try VocabularyPracticeValidator.validate(german.replacingOccurrences(of: "Garten", with: "Kindergarten"), request: de) }
    #expect(throws: GenerationError.self) { try VocabularyPracticeValidator.validate(german.replacingOccurrences(of: "Garten", with: "Garten-Haus"), request: de) }
    #expect(throws: GenerationError.self) { try VocabularyPracticeValidator.validate("The Garten is a beautiful place where my family meets every morning. We enjoy looking at the flowers and drinking tea together before we leave for work.", request: de) }
    #expect(throws: GenerationError.self) { try VocabularyPracticeValidator.validate(german + " This is an English sentence that must not appear here.", request: de) }
    let ru = VocabularyPracticeRequest(languageCode: "ru", expressions: [.init(id:"2",target:"кни́га",english:"book",meaning:"reading")])
    let russian = "Утром на столе лежала книга. Я открыл окно и сел рядом с сестрой. Мы долго читали вместе, а затем пошли гулять в сад, где под старым деревом нас уже ждали друзья."
    #expect(try VocabularyPracticeValidator.validate(russian, request: ru) == russian)
}

@Test func savedVocabularyAcceptsOnlyAttestedInflections() async throws {
    let planner = VocabularyPracticePlanner(registry: try LanguagePackRegistry(directory: languageDirectory))
    let word = VocabularyItem(id: "garden", draft: .init(englishLemma: "garden", targetLanguage: "ru", targetLemma: "сад", targetSurface: "сад", senseID: "outdoor plants", partOfSpeech: "noun"), createdAt: .now)
    let batch = try #require(try await planner.batches(items: [word], languageCode: "ru").first)
    #expect(batch.expressions[0].acceptedSurfaces.contains("саду"))
    let text = "Утром я долго гулял в саду вместе с сестрой. Мы смотрели на красивые цветы и разговаривали о новой книге, которую вчера принес наш старый друг после работы."
    #expect(try VocabularyPracticeValidator.validate(text, request: batch) == text)
    #expect(throws: GenerationError.self) { try VocabularyPracticeValidator.validate(text.replacingOccurrences(of:"саду",with:"садик"), request: batch) }
}
