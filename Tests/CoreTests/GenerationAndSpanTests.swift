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
    for bad in ["<think>hidden</think> " + prose, "Here is " + prose, String(prose.dropLast()), Array(repeating: "решение", count: 110).joined(separator: " ") + ".", "Too short."] {
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
    let db = try DatabaseManager()
    try await db.savePassage(text)
    #expect(try await db.recentPassages() == [text])
}

@Test func invalidUTF16AndRenderedOffsetsAreRejected() async throws {
    #expect(throws: DomainError.self) { try passage(range: .init(location: 1, length: 8)).renderedText() }
    #expect(throws: DomainError.self) { try passage(rendered: .init(location: 2, length: 7)).renderedText() }
    #expect(throws: DomainError.self) { try UTF16Span(location: Int.max, length: Int.max).range(in: "a") }
    #expect(throws: DomainError.self) { try UTF16Span(location: 0, length: 1).range(in: "e\u{301}") }
    let db = try DatabaseManager()
    await #expect(throws: DomainError.self) { try await db.savePassage(passage(rendered: .init(location: 0, length: 7))) }
    #expect(try await db.recentPassages().isEmpty)
}
