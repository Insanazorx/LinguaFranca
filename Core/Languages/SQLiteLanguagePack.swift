import Foundation
import GRDB

/// Read-only, indexed lexical lookup. The whole dictionary is never loaded into memory.
public actor SQLiteLanguagePack: LanguagePack {
    public nonisolated let metadata: LanguagePackMetadata
    private let database: DatabaseQueue
    private let preferredTranslations: [String:String]
    private let hasNounForms: Bool
    private let hasPracticeForms: Bool
    private let hasCaseForms: Bool
    private let hasSemiticForms: Bool
    private let hasLexicalForms: Bool
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
        hasPracticeForms = try database.read { try $0.tableExists("practiceForm") }
        hasCaseForms = try database.read { try $0.tableExists("caseForm") }
        hasSemiticForms = try database.read { try $0.tableExists("semForm") }
        hasLexicalForms = try database.read { try $0.tableExists("lexicalForm") }
        let policyURL = manifestURL.deletingPathExtension().appendingPathExtension("policy.json")
        if FileManager.default.fileExists(atPath: policyURL.path) {
            preferredTranslations = try JSONDecoder().decode([String:String].self, from: Data(contentsOf: policyURL))
        } else { preferredTranslations = [:] }
    }
    public func lookup(englishLemma: String) throws -> [LexicalEntry] {
        try database.read { db in
            let sql = hasSemiticForms ? "SELECT e.*,l.rootID AS rootID FROM entry e LEFT JOIN semLexeme l ON l.id=e.senseID WHERE e.lemma=? ORDER BY e.score DESC,e.senseID" : "SELECT * FROM entry WHERE lemma = ? ORDER BY score DESC, senseID"
            return try Row.fetchAll(db, sql:sql, arguments: [englishLemma.lowercased()])
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
                    var tags = ["definition": definition, "alternatives": translations, "form": "citation", "lexemeID": row["senseID"] as String]
                    if hasSemiticForms, let root: String = row["rootID"] { tags["rootID"] = root }
                    return LexicalEntry(englishLemma: lemma, targetLemma: target, senseID: row["senseID"],
                        partOfSpeech: row["pos"], contextExamples: [],
                        morphologicalTags: tags,
                        provenance: try JSONDecoder().decode([String:String].self, from: Data(provenance.utf8)))
                }
        }
    }
    public func lookupSense(englishLemma: String, senseID: String) throws -> LexicalEntry? {
        try lookup(englishLemma: englishLemma).first { $0.senseID == senseID }
    }
    public func inflect(_ entry: LexicalEntry, features: [String: String]) throws -> String? {
        guard features["requiresInflection"] != "true", features["case"] == nil || features["case"] == "nominative" else { return nil }
        if hasLexicalForms {
            let lemma=OfflineDictionary.key(entry.targetLemma)
            if entry.partOfSpeech == "noun",features["number"] == "plural" {
                let forms=try database.read { db in
                    try String.fetchAll(db,sql:"SELECT DISTINCT surface FROM lexicalForm WHERE lemmaKey=? AND pos='noun' AND number='plural' AND grammaticalCase=? ORDER BY surface",arguments:[lemma,metadata.languageCode == "la" ? "nominative":""])
                }
                return forms.count == 1 ? forms.first:nil
            }
            if entry.partOfSpeech == "verb" {
                guard let form=features["form"],["finite","infinitive","converb","participle"].contains(form) else {return nil}
                // Other tenses/aspects and gender agreement remain explicit adapter work.
                guard form != "finite" || features["tense"] == "present" else {return nil}
                let forms=try database.read { db in
                    try String.fetchAll(db,sql:"SELECT DISTINCT surface FROM lexicalForm WHERE lemmaKey=? AND pos='verb' AND form=? AND tense=? AND person=? AND number=? AND voice='active' ORDER BY surface",arguments:[lemma,form,features["tense"] ?? "",features["person"] ?? "",features["number"] ?? ""])
                }
                return forms.count == 1 ? forms.first:nil
            }
            if entry.partOfSpeech == "adjective" {return nil}
        }
        if hasSemiticForms {
            let forms=try database.read { db in
                try Row.fetchAll(db,sql:"SELECT * FROM semForm WHERE lexemeID=? AND status='attested' ORDER BY id LIMIT 1024",arguments:[entry.senseID]).map { r in
                    SemiticWordForm(id:r["id"],lexemeID:r["lexemeID"],surface:r["surface"],transliteration:r["transliteration"],source:r["source"],rootID:r["rootID"],tags:try JSONDecoder().decode([String].self,from:Data((r["tags"] as String).utf8)),status:.attested)
                }
            }
            return SemiticMorphologyAdapter.surface(forms:forms,entry:entry,features:features,language:metadata.languageCode)
        }
        if ["verb","adjective"].contains(entry.partOfSpeech) {
            guard hasPracticeForms, var form = features["form"] else { return nil }
            var tense = features["tense"] ?? "", person = features["person"] ?? "", number = features["number"] ?? "", gender = ""
            if entry.partOfSpeech == "adjective" { person = "" }
            if metadata.languageCode == "ru" {
                if form == "finite", tense == "past" {
                    guard features["habitual"] == "true" || features["allowGeneralPast"] == "true" else { return nil }
                    form = features["habitual"] == "true" ? "habitualPast" : "finitePast"; person = ""; gender = number == "plural" ? "" : features["gender"] ?? ""
                    guard number == "plural" || !gender.isEmpty else { return nil }
                } else if ["predicative","comparative"].contains(form) {
                    gender = number == "plural" ? "" : features["gender"] ?? ""
                    guard number == "plural" || !gender.isEmpty else { return nil }
                }
            } else if metadata.languageCode == "de", ["predicative","comparative"].contains(form) {
                tense = ""; person = ""; number = ""
            }
            let lemma = entry.targetLemma.replacingOccurrences(of:"\u{301}",with:"").precomposedStringWithCanonicalMapping.lowercased()
            let forms = try database.read { db in
                try String.fetchAll(db, sql:"SELECT DISTINCT surface FROM practiceForm WHERE lemma=? AND pos=? AND form=? AND tense=? AND person=? AND number=? AND gender=? ORDER BY surface", arguments:[lemma,entry.partOfSpeech,form,tense,person,number,gender])
            }
            if metadata.languageCode == "ru", entry.englishLemma == "write", lemma == "писать", tense == "present" {
                // писа́ть (write) and пи́сать (urinate) are separate OpenCorpora paradigms.
                // Only select an attested form from the documented writing paradigm.
                let writing = forms.filter { $0.hasPrefix("пиш") }
                return writing.count == 1 ? writing.first : nil
            }
            return forms.count == 1 ? forms.first : nil
        }
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
            && !surface.hasPrefix("-") && !surface.hasSuffix("-") && !surface.contains("...") && !surface.contains("…")
            && !entry.provenance.isEmpty && !context.isEmpty
    }
    public func nounPhrase(_ entry: LexicalEntry, number: String, grammaticalCase: String, article: String?) async throws -> String? {
        guard entry.partOfSpeech == "noun", hasCaseForms else { return nil }
        let lemma = entry.targetLemma.replacingOccurrences(of: "\u{301}", with: "").precomposedStringWithCanonicalMapping.lowercased()
        func forms(_ grammaticalCase: String) throws -> [(String,String)] {
            try database.read { db in
                try Row.fetchAll(db, sql: "SELECT DISTINCT surface,gender FROM caseForm WHERE lemma=? AND number=? AND grammaticalCase=? ORDER BY surface,gender", arguments: [lemma,number,grammaticalCase]).map { ($0["surface"],$0["gender"]) }
            }
        }
        var choices = try forms(grammaticalCase)
        // Russian spatial location may require the second locative: в лесу, not в лесе.
        if metadata.languageCode == "ru", grammaticalCase == "prepositional" {
            let locative = try forms("locative")
            if !locative.isEmpty {
                // The second locative is lexical/collocational, not a universal alternative.
                // в доме is ordinary location; на дому belongs to a different construction.
                if ["лес","сад","шкаф"].contains(lemma) { choices = locative }
                else if lemma != "дом" { return nil }
            }
        }
        guard Set(choices.map { $0.0 }).count == 1, let surface = choices.first?.0 else { return nil }
        if metadata.languageCode == "ru" { return surface }
        guard metadata.languageCode == "de" else { return nil }
        let genders = Set(choices.map { $0.1 })
        guard genders.count == 1, let gender = genders.first else { return nil }
        let key = number == "plural" ? "p" : gender
        let definite = ["nominative":["m":"der","f":"die","n":"das","p":"die"], "accusative":["m":"den","f":"die","n":"das","p":"die"], "dative":["m":"dem","f":"der","n":"dem","p":"den"], "genitive":["m":"des","f":"der","n":"des","p":"der"]]
        let indefinite = ["nominative":["m":"ein","f":"eine","n":"ein"], "accusative":["m":"einen","f":"eine","n":"ein"], "dative":["m":"einem","f":"einer","n":"einem"], "genitive":["m":"eines","f":"einer","n":"eines"]]
        if article == "the", let prefix = definite[grammaticalCase]?[key] { return prefix + " " + surface }
        if ["a","an"].contains(article ?? ""), let prefix = indefinite[grammaticalCase]?[key] { return prefix + " " + surface }
        return article == nil && number == "plural" ? surface : nil
    }
    public nonisolated func supportsPartOfSpeech(_ pos: String) -> Bool {
        ["noun", "adjective", "adverb", "verb", "conjunction", "preposition", "pronoun", "prepositional_phrase"].contains(pos)
    }
    public func practiceSurfaces(targetLemma: String, partOfSpeech: String) async throws -> [String] {
        if hasLexicalForms {
            return try await database.read { try String.fetchAll($0,sql:"SELECT DISTINCT surface FROM lexicalForm WHERE lemmaKey=? AND pos=? ORDER BY surface LIMIT 128",arguments:[OfflineDictionary.key(targetLemma),partOfSpeech]) }
        }
        if hasSemiticForms {
            return try await database.read { try String.fetchAll($0,sql:"SELECT DISTINCT f.surface FROM semForm f JOIN semLexeme l ON l.id=f.lexemeID WHERE l.normalized=? AND l.pos=? AND f.status='attested' ORDER BY f.surface LIMIT 128",arguments:[SemiticUnicode.key(targetLemma),partOfSpeech]) }
        }
        let lemma = targetLemma.replacingOccurrences(of: "\u{301}", with: "").precomposedStringWithCanonicalMapping.lowercased()
        if partOfSpeech == "noun", hasCaseForms {
            return try await database.read { try String.fetchAll($0, sql: "SELECT DISTINCT surface FROM caseForm WHERE lemma=? ORDER BY surface LIMIT 128", arguments: [lemma]) }
        }
        if ["verb","adjective"].contains(partOfSpeech), hasPracticeForms {
            return try await database.read { try String.fetchAll($0, sql: "SELECT DISTINCT surface FROM practiceForm WHERE lemma=? AND pos=? ORDER BY surface LIMIT 128", arguments: [lemma,partOfSpeech]) }
        }
        return []
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
    public init(directory: URL, additionalDirectories:[URL] = []) throws {
        let manifests = try ([directory]+additionalDirectories).flatMap { folder in
            try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("en-") && !$0.lastPathComponent.hasSuffix(".policy.json") }
        }
        let englishDirectory = directory.appendingPathComponent("_english",isDirectory:true)
        try self.init(packs: manifests.map { try SQLiteLanguagePack(manifestURL: $0) },
                      englishModelDirectory: FileManager.default.fileExists(atPath:englishDirectory.path) ? englishDirectory : nil)
    }
}
