import Foundation
import Testing
@testable import LinguaFrancaCore

@Test func scenariosDoNotRepeatEvenWithIdenticalSeeds() throws {
    var session = ReadingSession(), repeatSession = ReadingSession()
    var ids: Set<Int> = []
    var situations: Set<String> = []
    for attempt in 0..<100 {
        let scenario = try session.nextScenario(seed: 42)
        #expect(ids.insert(scenario.id).inserted)
        if attempt < 12 { #expect(situations.insert(scenario.situation).inserted) }
        #expect(try repeatSession.nextScenario(seed: 42) == scenario)
    }
    #expect(ReadingSession().passages.isEmpty)
}

@Test func earlierPassagesNeverEnterThePrompt() throws {
    let secret = "An earlier story about a lost umbrella in a remote village."
    var session = ReadingSession()
    let request = GenerationRequest(topic: "Travel", seed: 42, targetLanguageCodes: ["de", "ru"],
        vocabularyHints: [.init(englishLemma: "journey", languageCode: "de")],
        scenario: try session.nextScenario(seed: 42), previousPassages: [PassageFingerprint(secret)])
    try request.validate()
    #expect(!request.chatPrompt.contains(secret))
    #expect(request.prompt.contains("German and Russian"))
    #expect(request.prompt.contains("journey"))
    #expect(request.prompt.contains("Write entirely in English"))
    #expect(request.prompt.contains("International words may appear naturally"))
    #expect(request.prompt.contains(request.scenario!.situation))
}

@Test func duplicateAndNearDuplicateReadingsAreRejected() throws {
    let old = "Maya carried a broken wooden chair into the workshop. Her neighbour showed her how to mend the loose joint using a small wedge. By sunset the chair stood firmly beside the window, and she had gained confidence in her own skills."
    let reference = [PassageFingerprint(old)]
    #expect(throws: GenerationError.self) { try PassageNoveltyValidator.validate(old.uppercased(), previous: reference) }
    #expect(throws: GenerationError.self) {
        try PassageNoveltyValidator.validate(old.replacingOccurrences(of: "Maya", with: "David").replacingOccurrences(of: "sunset", with: "evening"), previous: reference)
    }
    try PassageNoveltyValidator.validate("A carpenter refused an urgent order when she discovered that the buyer expected an unsafe design. Instead of rushing, she explained the risk and offered a different plan. The buyer reluctantly agreed to wait until the following week.", previous: reference)
}

@Test func aNewSessionHasNoReadingsOrNoveltyHistory() throws {
    var session = ReadingSession()
    let text = GeneratedText(originalEnglish: "A traveller found a sheltered path beside the river.", topic: "Travel", cefrLevel: .b2, modelID: "fixture", seed: 42)
    try session.append(text)
    #expect(session.passages.count == 1 && session.fingerprints.count == 1)
    let relaunched = ReadingSession()
    #expect(relaunched.passages.isEmpty && relaunched.fingerprints.isEmpty)
    // Backgrounding does not replace this value; only a new process creates a new session.
    let stillRunning = session
    #expect(stillRunning.passages == [text])
}
