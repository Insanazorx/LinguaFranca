import Foundation
import GRDB

/// All database access is serialized away from SwiftUI. No database handles escape this actor.
public actor DatabaseManager {
    let queue: DatabaseQueue

    public init(path: String = ":memory:") throws {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.busyMode = .timeout(3)
        queue = try DatabaseQueue(path: path, configuration: configuration)
        try Self.migrator.migrate(queue)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_local_foundation") { db in
            try db.execute(sql: """
                CREATE TABLE studyDeck (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL CHECK(length(trim(name)) > 0),
                    nameKey TEXT NOT NULL UNIQUE,
                    createdAt REAL NOT NULL, updatedAt REAL NOT NULL
                );
                CREATE TABLE vocabularyItem (
                    id TEXT PRIMARY KEY NOT NULL,
                    englishLemma TEXT NOT NULL, englishKey TEXT NOT NULL,
                    targetLanguage TEXT NOT NULL, targetLemma TEXT NOT NULL, targetSurface TEXT NOT NULL,
                    senseID TEXT NOT NULL, partOfSpeech TEXT NOT NULL,
                    exampleEnglish TEXT NOT NULL, exampleMixed TEXT NOT NULL,
                    searchKey TEXT NOT NULL, createdAt REAL NOT NULL,
                    UNIQUE(englishKey, targetLanguage, targetLemma, senseID, partOfSpeech)
                );
                CREATE INDEX vocabulary_language ON vocabularyItem(targetLanguage);
                CREATE TABLE deckVocabulary (
                    deckID TEXT NOT NULL REFERENCES studyDeck(id) ON DELETE CASCADE,
                    vocabularyItemID TEXT NOT NULL REFERENCES vocabularyItem(id) ON DELETE CASCADE,
                    PRIMARY KEY(deckID, vocabularyItemID)
                );
                CREATE INDEX membership_vocabulary ON deckVocabulary(vocabularyItemID);
                CREATE TABLE srsCard (
                    id TEXT PRIMARY KEY NOT NULL,
                    vocabularyItemID TEXT NOT NULL REFERENCES vocabularyItem(id) ON DELETE CASCADE,
                    direction TEXT NOT NULL DEFAULT 'targetToEnglish',
                    state TEXT NOT NULL DEFAULT 'new' CHECK(state IN ('new','learning','review','relearning')),
                    dueAt REAL NOT NULL, stability REAL NOT NULL DEFAULT 0 CHECK(stability >= 0),
                    difficulty REAL NOT NULL DEFAULT 0 CHECK(difficulty >= 0),
                    repetitions INTEGER NOT NULL DEFAULT 0 CHECK(repetitions >= 0),
                    lapses INTEGER NOT NULL DEFAULT 0 CHECK(lapses >= 0), lastReviewedAt REAL,
                    schedulerVersion TEXT NOT NULL DEFAULT 'uninitialized',
                    UNIQUE(vocabularyItemID, direction)
                );
                CREATE INDEX card_due ON srsCard(state, dueAt);
                CREATE TABLE reviewLog (
                    id TEXT PRIMARY KEY NOT NULL,
                    cardID TEXT NOT NULL REFERENCES srsCard(id) ON DELETE CASCADE,
                    rating INTEGER NOT NULL CHECK(rating BETWEEN 1 AND 4),
                    reviewedAt REAL NOT NULL, elapsedTime REAL NOT NULL CHECK(elapsedTime >= 0),
                    scheduledInterval REAL NOT NULL CHECK(scheduledInterval >= 0),
                    priorState TEXT NOT NULL, resultingState TEXT NOT NULL,
                    schedulerVersion TEXT NOT NULL
                );
                CREATE INDEX review_date ON reviewLog(reviewedAt);
                CREATE TABLE generatedText (
                    id TEXT PRIMARY KEY NOT NULL,
                    originalEnglish TEXT NOT NULL, topic TEXT NOT NULL,
                    cefrLevel TEXT NOT NULL CHECK(cefrLevel IN ('B2','C1')),
                    generatedAt REAL NOT NULL, modelID TEXT NOT NULL, seed INTEGER NOT NULL CHECK(seed BETWEEN 0 AND 4294967295),
                    generationMetadata TEXT NOT NULL
                );
                CREATE INDEX passage_date ON generatedText(generatedAt DESC);
                CREATE TABLE replacement (
                    id TEXT PRIMARY KEY NOT NULL,
                    generatedTextID TEXT NOT NULL REFERENCES generatedText(id) ON DELETE CASCADE,
                    sourceStart INTEGER NOT NULL CHECK(sourceStart >= 0), sourceLength INTEGER NOT NULL CHECK(sourceLength > 0),
                    renderedStart INTEGER NOT NULL CHECK(renderedStart >= 0), renderedLength INTEGER NOT NULL CHECK(renderedLength > 0),
                    spanJSON TEXT NOT NULL,
                    UNIQUE(generatedTextID, sourceStart)
                );
                CREATE INDEX replacement_source ON replacement(generatedTextID, sourceStart);
                CREATE TABLE settings (id INTEGER PRIMARY KEY CHECK(id = 1), json TEXT NOT NULL, updatedAt REAL NOT NULL);
                """
            )
        }
        migrator.registerMigration("v2_ephemeral_reading_sessions") { db in
            // Readings are now process-local. User vocabulary/examples and SRS history are independent.
            try db.execute(sql: "DROP TABLE replacement; DROP TABLE generatedText;")
        }
        migrator.registerMigration("v3_semitic_vocabulary_references") { db in
            try db.execute(sql:"CREATE TABLE vocabularyLexicalReference(vocabularyItemID TEXT PRIMARY KEY NOT NULL REFERENCES vocabularyItem(id) ON DELETE CASCADE, json TEXT NOT NULL)")
        }
        migrator.registerMigration("v4_fsrs6_reviews") { db in
            try db.execute(sql: """
                ALTER TABLE srsCard ADD COLUMN learningStep INTEGER NOT NULL DEFAULT 0 CHECK(learningStep >= 0);
                ALTER TABLE srsCard ADD COLUMN progress TEXT NOT NULL DEFAULT 'studying' CHECK(progress IN ('forgotten','studying','learned'));
                UPDATE srsCard SET progress = CASE WHEN state = 'review' THEN 'learned' WHEN state = 'relearning' THEN 'forgotten' ELSE 'studying' END;
                ALTER TABLE reviewLog ADD COLUMN priorCardJSON TEXT;
                ALTER TABLE reviewLog ADD COLUMN resultingCardJSON TEXT;
                CREATE INDEX card_progress ON srsCard(progress);
                """)
        }
        migrator.registerMigration("v5_opt_in_saved_readings") { db in
            try db.execute(sql:"""
                CREATE TABLE savedReading (
                    id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL CHECK(length(trim(title))>0),
                    preview TEXT NOT NULL,
                    passageJSON TEXT NOT NULL,
                    translationsJSON TEXT NOT NULL,
                    savedAt REAL NOT NULL,
                    updatedAt REAL NOT NULL
                );
                CREATE INDEX savedReading_updated ON savedReading(updatedAt DESC);
                """)
        }
        return migrator
    }

    public func decks() async throws -> [StudyDeck] {
        try await queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT d.*, count(v.vocabularyItemID) AS wordCount FROM studyDeck d
                LEFT JOIN deckVocabulary v ON d.id = v.deckID GROUP BY d.id ORDER BY d.createdAt, d.id
                """
            ).map(Self.deck)
        }
    }

    @discardableResult public func createDeck(name: String, now: Date = .now) async throws -> String {
        let clean = try Self.deckName(name), id = UUID().uuidString
        try await queue.write { db in
            if try String.fetchOne(db, sql: "SELECT id FROM studyDeck WHERE nameKey = ?", arguments: [Self.key(clean)]) != nil {
                throw DomainError.invalidInput("A list with this name already exists.")
            }
            try db.execute(sql: "INSERT INTO studyDeck VALUES (?, ?, ?, ?, ?)",
                           arguments: [id, clean, Self.key(clean), now.timeIntervalSince1970, now.timeIntervalSince1970])
        }
        return id
    }

    public func renameDeck(id: String, name: String, now: Date = .now) async throws {
        let clean = try Self.deckName(name)
        try await queue.write { db in
            if try String.fetchOne(db, sql: "SELECT id FROM studyDeck WHERE nameKey = ? AND id != ?", arguments: [Self.key(clean), id]) != nil {
                throw DomainError.invalidInput("A list with this name already exists.")
            }
            try db.execute(sql: "UPDATE studyDeck SET name = ?, nameKey = ?, updatedAt = ? WHERE id = ?",
                           arguments: [clean, Self.key(clean), now.timeIntervalSince1970, id])
            guard db.changesCount == 1 else { throw DomainError.missingRecord }
        }
    }

    public func deleteDeck(id: String) async throws {
        // Deleting a list removes memberships, never shared words or study history.
        try await queue.write { db in try db.execute(sql: "DELETE FROM studyDeck WHERE id = ?", arguments: [id]) }
    }

    public func vocabulary(search: String = "", deckID: String? = nil) async throws -> [VocabularyItem] {
        let query = Self.key(search.trimmingCharacters(in: .whitespacesAndNewlines))
        return try await queue.read { db in
            var sql = "SELECT v.*, r.json AS lexicalReferenceJSON, c.progress AS studyProgress FROM vocabularyItem v LEFT JOIN vocabularyLexicalReference r ON r.vocabularyItemID=v.id LEFT JOIN srsCard c ON c.vocabularyItemID=v.id AND c.direction='targetToEnglish' WHERE instr(v.searchKey, ?) > 0"
            var arguments: StatementArguments = [query]
            if let deckID {
                sql += " AND EXISTS (SELECT 1 FROM deckVocabulary d WHERE d.vocabularyItemID = v.id AND d.deckID = ?)"
                arguments += [deckID]
            }
            sql += " ORDER BY v.createdAt DESC, v.id"
            return try Row.fetchAll(db, sql: sql, arguments: arguments).map(Self.word)
        }
    }

    @discardableResult public func saveVocabulary(_ draft: VocabularyDraft, inDeck deckID: String, now: Date = .now) async throws -> String {
        let value = try draft.validated()
        let wordID = UUID().uuidString, cardID = UUID().uuidString
        return try await queue.write { db in
            guard try String.fetchOne(db, sql: "SELECT id FROM studyDeck WHERE id = ?", arguments: [deckID]) != nil
            else { throw DomainError.missingRecord }
            let existing = try String.fetchOne(db, sql: """
                SELECT id FROM vocabularyItem WHERE englishKey = ? AND targetLanguage = ?
                AND targetLemma = ? AND senseID = ? AND partOfSpeech = ?
                """, arguments: [Self.key(value.englishLemma), value.targetLanguage, value.targetLemma, value.senseID, value.partOfSpeech])
            let id = existing ?? wordID
            if existing == nil {
                try db.execute(sql: "INSERT INTO vocabularyItem VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    arguments: [id, value.englishLemma, Self.key(value.englishLemma), value.targetLanguage, value.targetLemma,
                                value.targetSurface, value.senseID, value.partOfSpeech, value.exampleEnglish, value.exampleMixed,
                                Self.searchKey(value), now.timeIntervalSince1970])
                try db.execute(sql: "INSERT INTO srsCard(id, vocabularyItemID, dueAt) VALUES (?, ?, ?)",
                               arguments: [cardID, id, now.timeIntervalSince1970])
            }
            try db.execute(sql: "INSERT OR IGNORE INTO deckVocabulary VALUES (?, ?)", arguments: [deckID, id])
            if let reference = value.lexicalReference {
                let json = String(decoding:try JSONEncoder().encode(reference),as:UTF8.self)
                try db.execute(sql:"INSERT OR REPLACE INTO vocabularyLexicalReference VALUES(?,?)",arguments:[id,json])
            }
            try db.execute(sql: "UPDATE studyDeck SET updatedAt = ? WHERE id = ?", arguments: [now.timeIntervalSince1970, deckID])
            return id
        }
    }

    public func updateVocabulary(id: String, draft: VocabularyDraft) async throws {
        let v = try draft.validated()
        try await queue.write { db in
            if try String.fetchOne(db, sql: """
                SELECT id FROM vocabularyItem WHERE englishKey = ? AND targetLanguage = ? AND targetLemma = ?
                AND senseID = ? AND partOfSpeech = ? AND id != ?
                """, arguments: [Self.key(v.englishLemma), v.targetLanguage, v.targetLemma, v.senseID, v.partOfSpeech, id]) != nil {
                throw DomainError.duplicateVocabulary
            }
            try db.execute(sql: """
                UPDATE vocabularyItem SET englishLemma = ?, englishKey = ?, targetLanguage = ?, targetLemma = ?,
                targetSurface = ?, senseID = ?, partOfSpeech = ?, exampleEnglish = ?, exampleMixed = ?, searchKey = ? WHERE id = ?
                """, arguments: [v.englishLemma, Self.key(v.englishLemma), v.targetLanguage, v.targetLemma, v.targetSurface,
                                  v.senseID, v.partOfSpeech, v.exampleEnglish, v.exampleMixed, Self.searchKey(v), id])
            guard db.changesCount == 1 else { throw DomainError.missingRecord }
            if let reference = v.lexicalReference {
                try db.execute(sql:"INSERT OR REPLACE INTO vocabularyLexicalReference VALUES(?,?)",arguments:[id,String(decoding:try JSONEncoder().encode(reference),as:UTF8.self)])
            } else {
                try db.execute(sql:"DELETE FROM vocabularyLexicalReference WHERE vocabularyItemID=?",arguments:[id])
            }
        }
    }

    public func deleteVocabulary(id: String) async throws {
        try await queue.write { db in try db.execute(sql: "DELETE FROM vocabularyItem WHERE id = ?", arguments: [id]) }
    }

    public func removeVocabulary(id: String, fromDeck deckID: String) async throws {
        try await queue.write { db in
            try db.execute(sql: "DELETE FROM deckVocabulary WHERE vocabularyItemID = ? AND deckID = ?", arguments: [id, deckID])
        }
    }

    public func settings() async throws -> AppSettings {
        try await queue.read { db in
            guard let json = try String.fetchOne(db, sql: "SELECT json FROM settings WHERE id = 1") else { return AppSettings() }
            let value = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
            try value.validate()
            return value
        }
    }

    public func saveSettings(_ settings: AppSettings) async throws {
        try settings.validate()
        let json = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        try await queue.write { db in
            try db.execute(sql: "INSERT INTO settings VALUES (1, ?, ?) ON CONFLICT(id) DO UPDATE SET json = excluded.json, updatedAt = excluded.updatedAt",
                           arguments: [json, Date.now.timeIntervalSince1970])
        }
    }

    public func storageBytes() async throws -> Int64 {
        try await queue.read { db in
            let pages = try Int64.fetchOne(db, sql: "PRAGMA page_count") ?? 0
            let size = try Int64.fetchOne(db, sql: "PRAGMA page_size") ?? 0
            return pages * size
        }
    }

    public func studySummary(deckID: String? = nil, now: Date = .now, calendar: Calendar = .current) async throws -> StudySummary {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return try await queue.read { db in
            let filter = deckID == nil ? "" : " AND c.vocabularyItemID IN (SELECT vocabularyItemID FROM deckVocabulary WHERE deckID = ?)"
            var dueArgs: StatementArguments = [now.timeIntervalSince1970]
            var newArgs: StatementArguments = []
            var reviewArgs: StatementArguments = [start.timeIntervalSince1970, end.timeIntervalSince1970]
            if let deckID { dueArgs += [deckID]; newArgs += [deckID]; reviewArgs += [deckID] }
            let due = try Int.fetchOne(db, sql: "SELECT count(*) FROM srsCard c WHERE state != 'new' AND dueAt <= ?" + filter, arguments: dueArgs) ?? 0
            let new = try Int.fetchOne(db, sql: "SELECT count(*) FROM srsCard c WHERE state = 'new'" + filter, arguments: newArgs) ?? 0
            let reviewed = try Int.fetchOne(db, sql: "SELECT count(*) FROM reviewLog r JOIN srsCard c ON c.id = r.cardID WHERE r.reviewedAt >= ? AND r.reviewedAt < ?" + filter, arguments: reviewArgs) ?? 0
            return StudySummary(newCards: new, dueCards: due, reviewedToday: reviewed)
        }
    }

    private static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .precomposedStringWithCanonicalMapping
    }
    private static func searchKey(_ value: VocabularyDraft) -> String {
        key([value.englishLemma, value.targetLemma, value.targetSurface, value.senseID, value.exampleEnglish].joined(separator: " "))
    }
    private static func deckName(_ name: String) throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 80 else { throw DomainError.invalidInput("List names must contain 1–80 characters.") }
        return clean
    }
    private static func deck(_ row: Row) -> StudyDeck {
        StudyDeck(id: row["id"], name: row["name"], createdAt: Date(timeIntervalSince1970: row["createdAt"]),
                  updatedAt: Date(timeIntervalSince1970: row["updatedAt"]), wordCount: row["wordCount"])
    }
    static func word(_ row: Row) -> VocabularyItem {
        let json: String? = row["lexicalReferenceJSON"]
        let reference = json.flatMap { try? JSONDecoder().decode(SemiticVocabularyReference.self,from:Data($0.utf8)) }
        return VocabularyItem(id: row["id"], draft: VocabularyDraft(englishLemma: row["englishLemma"], targetLanguage: row["targetLanguage"],
            targetLemma: row["targetLemma"], targetSurface: row["targetSurface"], senseID: row["senseID"], partOfSpeech: row["partOfSpeech"],
            exampleEnglish: row["exampleEnglish"], exampleMixed: row["exampleMixed"],lexicalReference:reference), createdAt: Date(timeIntervalSince1970: row["createdAt"]), studyProgress: StudyProgress(rawValue: row["studyProgress"] ?? "studying") ?? .studying)
    }
}
