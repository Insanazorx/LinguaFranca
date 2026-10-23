import Foundation
import GRDB

/// Read-only, indexed lexical lookup. The whole dictionary is never loaded into memory.
public actor SQLiteLanguagePack: LanguagePack {
    public nonisolated let metadata: LanguagePackMetadata
    private let database: DatabaseQueue
    private let preferredTranslations: [String:String]
    private let hasNounForms: Bool
    public init(manifestURL: URL) throws {
        metadata = try JSONDecoder().decode(LanguagePackMetadata.self, from: Data(contentsOf: manifestURL))
        guard metadata.schemaVersion == 1,
              metadata.lexiconDatabaseName == URL(fileURLWithPath: metadata.lexiconDatabaseName).lastPathComponent
        else { throw DomainError.invalidInput("Unsupported language pack.") }
        var configuration = Configuration()
        configuration.readonly = true
        database = try DatabaseQueue(path: manifestURL.deletingLastPathComponent()
            .appendingPathComponent(metadata.lexiconDatabaseName).path, configuration: configuration)
        hasNounForms = try database.read { try $0.tableExists("nounForm") }
        let policyURL = manifestURL.deletingPathExtension().appendingPathExtension("policy.json")
        if FileManager.default.fileExists(atPath: policyURL.path) {
            preferredTranslations = try JSONDecoder().decode([String:String].self, from: Data(contentsOf: policyURL))
        } else { preferredTranslations = [:] }
    }
    public func lookup(englishLemma: String) throws -> [LexicalEntry] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM entry WHERE lemma = ? ORDER BY score DESC, senseID", arguments: [englishLemma.lowercased()])
                .compactMap { row in
                    let translations: String = row["translations"], provenance: String = row["provenance"]
                    let alternatives = try JSONDecoder().decode([String].self, from: Data(translations.utf8))
                    guard let first = alternatives.first else { return nil }
                    let lemma: String = row["lemma"]
                    // Preferences only choose among translations actually present in this sense.
                    // Stress marks are optional for display; ё and other letters are preserved.
                    func key(_ value: String) -> String { value.replacingOccurrences(of: "\u{301}", with: "").precomposedStringWithCanonicalMapping }
                    let preferred = preferredTranslations[lemma]
                    let target = preferred.flatMap { requested in alternatives.first { key($0) == key(requested) } } ?? first
                    let definition: String = row["definition"]
                    return LexicalEntry(englishLemma: lemma, targetLemma: target, senseID: row["senseID"],
                        partOfSpeech: row["pos"], contextExamples: [],
                        morphologicalTags: ["definition": definition, "alternatives": translations, "form": "citation"],
                        provenance: try JSONDecoder().decode([String:String].self, from: Data(provenance.utf8)))
                }
        }
    }
    public func lookupSense(englishLemma: String, senseID: String) throws -> LexicalEntry? {
        try lookup(englishLemma: englishLemma).first { $0.senseID == senseID }
    }
    public func inflect(_ entry: LexicalEntry, features: [String: String]) throws -> String? {
        guard features["requiresInflection"] != "true", features["case"] == nil || features["case"] == "nominative" else { return nil }
        if features["number"] == "plural" {
            guard hasNounForms, entry.partOfSpeech == "noun" else { return nil }
            let key = entry.targetLemma.replacingOccurrences(of:"\u{301}",with:"").precomposedStringWithCanonicalMapping.lowercased()
            let forms = try database.read { db in
                try String.fetchAll(db,sql:"SELECT DISTINCT surface FROM nounForm WHERE lemma=? AND number='plural' ORDER BY surface",arguments:[key])
            }
            // Bank→Banken/Bänke and similar sense-dependent plurals need a stronger link.
            return forms.count == 1 ? forms.first : nil
        }
        return entry.targetLemma
    }
    public func validateReplacement(_ entry: LexicalEntry, surface: String, context: String) -> Bool {
        supportsPartOfSpeech(entry.partOfSpeech) && !surface.isEmpty && surface.count <= 100
            && !surface.hasPrefix("-") && !surface.hasSuffix("-") && !surface.contains("...")
            && !entry.provenance.isEmpty && !context.isEmpty
    }
    public nonisolated func supportsPartOfSpeech(_ pos: String) -> Bool {
        ["noun", "adverb", "conjunction", "preposition", "pronoun"].contains(pos)
    }
}

public struct LanguagePackRegistry: Sendable {
    public let packs: [any LanguagePack]
    let englishTagger: BundledEnglishTagger?
    public init(packs: [any LanguagePack], englishModelDirectory: URL? = nil) throws {
        guard Set(packs.map { $0.metadata.languageCode }).count == packs.count else {
            throw DomainError.invalidInput("Duplicate language packs.")
        }
        self.packs = packs.sorted { $0.metadata.languageCode < $1.metadata.languageCode }
        englishTagger = try englishModelDirectory.map { try BundledEnglishTagger(directory:$0) }
    }
    public init(directory: URL) throws {
        let manifests = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "coverage.json" && !$0.lastPathComponent.hasSuffix(".policy.json") }
        let englishDirectory = directory.appendingPathComponent("_english",isDirectory:true)
        try self.init(packs: manifests.map { try SQLiteLanguagePack(manifestURL: $0) },
                      englishModelDirectory: FileManager.default.fileExists(atPath:englishDirectory.path) ? englishDirectory : nil)
    }
}
