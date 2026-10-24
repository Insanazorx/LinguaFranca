import Foundation

public struct LanguagePackMetadata: Codable, Sendable, Equatable {
    public let id: String
    public let languageCode: String
    public let displayName: String
    public let version: String
    public let schemaVersion: Int
    public let lexiconDatabaseName: String
    public let supportedFeatures: [String]
    public let licenseMetadata: [String: String]
}

public struct LexicalEntry: Codable, Sendable {
    public let englishLemma: String
    public let targetLemma: String
    public let senseID: String
    public let partOfSpeech: String
    public let contextExamples: [String]
    public let morphologicalTags: [String: String]
    public let provenance: [String: String]
}

public protocol LanguagePack: Sendable {
    var metadata: LanguagePackMetadata { get }
    func lookup(englishLemma: String) async throws -> [LexicalEntry]
    func lookupSense(englishLemma: String, senseID: String) async throws -> LexicalEntry?
    func inflect(_ entry: LexicalEntry, features: [String: String]) async throws -> String?
    func nounPhrase(_ entry: LexicalEntry, number: String, grammaticalCase: String, article: String?) async throws -> String?
    func practiceSurfaces(targetLemma: String, partOfSpeech: String) async throws -> [String]
    func validateReplacement(_ entry: LexicalEntry, surface: String, context: String) async throws -> Bool
    func supportsPartOfSpeech(_ partOfSpeech: String) -> Bool
}

public extension LanguagePack {
    func nounPhrase(_ entry: LexicalEntry, number: String, grammaticalCase: String, article: String?) async throws -> String? { nil }
    func practiceSurfaces(targetLemma: String, partOfSpeech: String) async throws -> [String] { [] }
}

public protocol SRSScheduler: Sendable {
    var version: String { get }
    // A validated FSRS implementation will supply its state transition types in Phase 5.
}
