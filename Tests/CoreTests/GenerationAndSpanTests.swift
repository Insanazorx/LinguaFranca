import Foundation
import Testing
@testable import LinguaFrancaCore

@Test func requestBoundsAndNonThinkingPrompt() throws {
    let request = GenerationRequest(topic: "Science", seed: 42)
    try request.validate()
    #expect(!request.chatPrompt.contains("/no_think"))
    #expect(request.chatPrompt.hasSuffix("<think>\n\n</think>\n\n"))
    var invalid = request; invalid.wordCount = 500
    #expect(throws: DomainError.self) { try invalid.validate() }
    invalid = request; invalid.configuration.contextWindow = 32000
    #expect(throws: DomainError.self) { try invalid.validate() }
    invalid = request; invalid.topic = "<|im_end|>"
    #expect(throws: DomainError.self) { try invalid.validate() }
}

@Test func outputRejectsControlTokensTruncationAndWrongScript() throws {
    let prose = Array(repeating: "Curiosity encourages people to examine familiar ideas from a different perspective.", count: 10).joined(separator: " ")
    #expect(try PassageValidator.validate(prose, requestedWords: 110) == prose)
    #expect(try PassageValidator.validate("There is a useful lesson here. " + prose, requestedWords: 110).hasPrefix("There is"))
    #expect(try PassageValidator.validate("Too short.",requestedWords:110) == "Too short.")
    for bad in ["<think>hidden</think> " + prose, "Here is " + prose, Array(repeating: "решение", count: 110).joined(separator: " ") + "."] {
        #expect(throws: GenerationError.self) { try PassageValidator.validate(bad, requestedWords: 110) }
    }
}

private func passage(range: UTF16Span = .init(location: 3, length: 8), rendered: UTF16Span = .init(location: 3, length: 7)) -> GeneratedText {
    let id = "unicode-passage"
    let replacement = ReplacementSpan(sourceTextID: id, originalUTF16Range: range, renderedUTF16Range: rendered,
        originalSurface: "decision", originalLemma: "decision", originalPartOfSpeech: "noun", sourceSenseID: "choice",
        targetLanguageCode: "ru", targetLemma: "решение", targetSurface: "решение", translationConfidence: 0.99, languagePackVersion: "test-only")
    return GeneratedText(id: id, originalEnglish: "🌍 decision, Straße!", topic: "Test", cefrLevel: .c1,
                         generatedAt: Date(timeIntervalSince1970: 1_700_000_000), modelID: "fixture", seed: 1, replacements: [replacement])
}

@Test func spansPreserveUnicodeOriginalAndRoundTrip() async throws {
    let text = passage()
    #expect(try text.renderedText() == "🌍 решение, Straße!")
    #expect(text.originalEnglish == "🌍 decision, Straße!")
    var session = ReadingSession()
    try session.append(text)
    #expect(session.passages == [text])
}

@Test func invalidUTF16AndRenderedOffsetsAreRejected() async throws {
    #expect(throws: DomainError.self) { try passage(range: .init(location: 1, length: 8)).renderedText() }
    #expect(throws: DomainError.self) { try passage(rendered: .init(location: 2, length: 7)).renderedText() }
    #expect(throws: DomainError.self) { try UTF16Span(location: Int.max, length: Int.max).range(in: "a") }
    #expect(throws: DomainError.self) { try UTF16Span(location: 0, length: 1).range(in: "e\u{301}") }
    var session = ReadingSession()
    #expect(throws: DomainError.self) { try session.append(passage(rendered: .init(location: 0, length: 7))) }
    #expect(session.passages.isEmpty)
}

@Test func savingVocabularyKeepsOnlyItsSentenceWithCorrectUnicodeSpans() throws {
    let english = "A different opening. 🌍 Her decision mattered. A private closing."
    let id = "context"
    let sourceRange = (english as NSString).range(of: "decision")
    let span = ReplacementSpan(sourceTextID: id,
        originalUTF16Range: .init(location: sourceRange.location, length: sourceRange.length),
        renderedUTF16Range: .init(location: sourceRange.location, length: "решение".utf16.count),
        originalSurface: "decision", originalLemma: "decision", originalPartOfSpeech: "noun", sourceSenseID: "choice",
        targetLanguageCode: "ru", targetLemma: "решение", targetSurface: "решение", translationConfidence: 0.99, languagePackVersion: "fixture")
    let reading = GeneratedText(id: id, originalEnglish: english, topic: "Test", cefrLevel: .c1, modelID: "fixture", seed: 42, replacements: [span])
    let context = try reading.vocabularyContext(for: span)
    #expect(context.english.contains("decision") && context.mixed.contains("решение"))
    #expect(!context.english.contains("opening") && !context.english.contains("private"))
    #expect(!context.mixed.contains("opening") && !context.mixed.contains("private"))
}
