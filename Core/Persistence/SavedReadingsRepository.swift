import Foundation
import GRDB

public struct SavedReadingSummary: Sendable, Equatable, Identifiable {
    public let id,title,preview:String
    public let savedAt,updatedAt:Date
}
public struct SavedReading: Sendable, Equatable {
    public let title:String
    public let passage:GeneratedText
    public let translations:[String:TargetReading]
}

extension DatabaseManager {
    public func savedReadings() async throws -> [SavedReadingSummary] {
        try await queue.read { db in
            try Row.fetchAll(db,sql:"SELECT id,title,preview,savedAt,updatedAt FROM savedReading ORDER BY updatedAt DESC,id").map {
                .init(id:$0["id"],title:$0["title"],preview:$0["preview"],savedAt:Date(timeIntervalSince1970:$0["savedAt"]),updatedAt:Date(timeIntervalSince1970:$0["updatedAt"]))
            }
        }
    }
    public func savedReading(id:String) async throws -> SavedReading {
        try await queue.read { db in
            guard let row=try Row.fetchOne(db,sql:"SELECT * FROM savedReading WHERE id=?",arguments:[id]) else {throw DomainError.missingRecord}
            let passage=try JSONDecoder().decode(GeneratedText.self,from:Data((row["passageJSON"] as String).utf8))
            _=try passage.renderedText()
            return SavedReading(title:row["title"],passage:passage,translations:try JSONDecoder().decode([String:TargetReading].self,from:Data((row["translationsJSON"] as String).utf8)))
        }
    }
    /// Explicit user opt-in only. Ordinary generation never calls this method.
    public func saveReading(_ passage:GeneratedText,title:String,translations:[String:TargetReading]=[:],now:Date = .now) async throws {
        _=try passage.renderedText()
        let clean=title.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !clean.isEmpty,clean.count<=200 else {throw DomainError.invalidInput("Choose a title under 200 characters.")}
        for (language,reading) in translations {
            guard reading.languageCode==language else {throw DomainError.invalidInput("The saved translation has the wrong language.")}
            try reading.validate(for:passage)
        }
        let json=String(decoding:try JSONEncoder().encode(passage),as:UTF8.self)
        try await queue.write { db in
            var kept:[String:TargetReading]=[:]
            if let existing=try Row.fetchOne(db,sql:"SELECT passageJSON,translationsJSON FROM savedReading WHERE id=?",arguments:[passage.id]) {
                let old=try JSONDecoder().decode(GeneratedText.self,from:Data((existing["passageJSON"] as String).utf8))
                guard old.originalEnglish==passage.originalEnglish else {throw DomainError.invalidInput("The saved source text has changed.")}
                kept=try JSONDecoder().decode([String:TargetReading].self,from:Data((existing["translationsJSON"] as String).utf8))
            }
            kept.merge(translations,uniquingKeysWith:{_,new in new})
            let readings=String(decoding:try JSONEncoder().encode(kept),as:UTF8.self)
            try db.execute(sql:"""
                INSERT INTO savedReading(id,title,preview,passageJSON,translationsJSON,savedAt,updatedAt) VALUES(?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET title=excluded.title,preview=excluded.preview,passageJSON=excluded.passageJSON,translationsJSON=excluded.translationsJSON,updatedAt=excluded.updatedAt
                """,arguments:[passage.id,clean,String(passage.originalEnglish.prefix(180)),json,readings,now.timeIntervalSince1970,now.timeIntervalSince1970])
        }
    }
    public func saveReadingTranslation(_ reading:TargetReading) async throws {
        try await queue.write { db in
            guard let row=try Row.fetchOne(db,sql:"SELECT passageJSON,translationsJSON FROM savedReading WHERE id=?",arguments:[reading.sourceTextID]) else {throw DomainError.missingRecord}
            let passage=try JSONDecoder().decode(GeneratedText.self,from:Data((row["passageJSON"] as String).utf8))
            try reading.validate(for:passage)
            var translations=try JSONDecoder().decode([String:TargetReading].self,from:Data((row["translationsJSON"] as String).utf8))
            translations[reading.languageCode]=reading
            let json=String(decoding:try JSONEncoder().encode(translations),as:UTF8.self)
            try db.execute(sql:"UPDATE savedReading SET translationsJSON=?,updatedAt=? WHERE id=?",arguments:[json,Date.now.timeIntervalSince1970,reading.sourceTextID])
        }
    }
    public func renameReading(id:String,title:String) async throws {
        let clean=title.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !clean.isEmpty,clean.count<=200 else {throw DomainError.invalidInput("Choose a title under 200 characters.")}
        try await queue.write { db in
            try db.execute(sql:"UPDATE savedReading SET title=?,updatedAt=? WHERE id=?",arguments:[clean,Date.now.timeIntervalSince1970,id])
            guard db.changesCount==1 else {throw DomainError.missingRecord}
        }
    }
    public func deleteReading(id:String) async throws {
        try await queue.write {db in try db.execute(sql:"DELETE FROM savedReading WHERE id=?",arguments:[id])}
    }
}
