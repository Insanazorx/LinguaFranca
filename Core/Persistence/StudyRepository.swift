import Foundation
import GRDB

extension DatabaseManager {
    /// Voluntary practice is independent of due dates and daily admission limits.
    public func practiceCards(deckID:String?=nil,forgottenOnly:Bool=false) async throws -> [StudyCard] {
        try await queue.read { db in
            var sql="""
                SELECT v.*,r.json AS lexicalReferenceJSON,c.progress AS studyProgress,
                c.id AS cardID,c.vocabularyItemID,c.state,c.dueAt,c.stability,c.difficulty,
                c.repetitions,c.lapses,c.lastReviewedAt,c.learningStep,c.schedulerVersion,c.progress
                FROM srsCard c JOIN vocabularyItem v ON v.id=c.vocabularyItemID
                LEFT JOIN vocabularyLexicalReference r ON r.vocabularyItemID=v.id
                WHERE c.direction='targetToEnglish'
                """
            var args:StatementArguments=[]
            if let deckID { sql += " AND EXISTS(SELECT 1 FROM deckVocabulary m WHERE m.vocabularyItemID=v.id AND m.deckID=?)";args += [deckID] }
            if forgottenOnly { sql += " AND c.progress='forgotten'" }
            sql += " ORDER BY v.targetLanguage,v.englishKey,v.id"
            return try Row.fetchAll(db,sql:sql,arguments:args).map { .init(card:Self.card($0,idColumn:"cardID"),word:Self.word($0)) }
        }
    }
    /// Due learning cards are never hidden by the daily admission target. Shared words occur once.
    public func studyQueue(deckID: String? = nil, dailyTarget: Int = 20, now: Date = .now, calendar: Calendar = .current) async throws -> [StudyCard] {
        guard (1...500).contains(dailyTarget) else { throw DomainError.invalidInput("Invalid daily target.") }
        let start = calendar.startOfDay(for: now), end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        return try await queue.read { db in
            let admissions = try Int.fetchOne(db, sql: "SELECT count(DISTINCT cardID) FROM reviewLog WHERE reviewedAt >= ? AND reviewedAt < ?", arguments: [start.timeIntervalSince1970,end.timeIntervalSince1970]) ?? 0
            let filter = deckID == nil ? "" : " AND EXISTS(SELECT 1 FROM deckVocabulary m WHERE m.vocabularyItemID=c.vocabularyItemID AND m.deckID=?)"
            var args: StatementArguments = [now.timeIntervalSince1970]
            if let deckID { args += [deckID] }
            let rows = try Row.fetchAll(db, sql: "SELECT c.* FROM srsCard c WHERE c.dueAt <= ?" + filter + " ORDER BY CASE WHEN state IN ('learning','relearning') THEN 0 WHEN state='review' THEN 1 ELSE 2 END, dueAt, id LIMIT 500", arguments: args)
            var remaining = max(0, dailyTarget-admissions)
            var result: [StudyCard] = []
            for row in rows {
                let card = Self.card(row)
                let today = try Bool.fetchOne(db,sql:"SELECT EXISTS(SELECT 1 FROM reviewLog WHERE cardID=? AND reviewedAt>=? AND reviewedAt<?)",arguments:[card.id,start.timeIntervalSince1970,end.timeIntervalSince1970]) ?? false
                if !today && ![CardState.learning,.relearning].contains(card.state) {
                    guard remaining > 0 else { continue }; remaining -= 1
                }
                guard let word = try Row.fetchOne(db,sql:"SELECT v.*,r.json AS lexicalReferenceJSON,c.progress AS studyProgress FROM vocabularyItem v JOIN srsCard c ON c.vocabularyItemID=v.id LEFT JOIN vocabularyLexicalReference r ON r.vocabularyItemID=v.id WHERE c.id=?",arguments:[card.id]) else { continue }
                result.append(StudyCard(card:card,word:Self.word(word)))
            }
            return result
        }
    }

    /// Card update and immutable review event are a single transaction. A stale/double swipe cannot write twice.
    @discardableResult public func reviewCard(_ expected: SRSCard, rating: ReviewRating, elapsedTime: TimeInterval, desiredRetention: Double = 0.9, now: Date = .now, eventID: String = UUID().uuidString) async throws -> SRSCard {
        guard elapsedTime.isFinite, elapsedTime >= 0, !eventID.isEmpty else { throw DomainError.invalidInput("Invalid review event.") }
        let scheduler = try FSRS6(desiredRetention: desiredRetention)
        return try await queue.write { db in
            guard let row = try Row.fetchOne(db,sql:"SELECT * FROM srsCard WHERE id=?",arguments:[expected.id]) else { throw DomainError.missingRecord }
            let current = Self.card(row)
            if let saved = try String.fetchOne(db,sql:"SELECT resultingCardJSON FROM reviewLog WHERE id=? AND cardID=?",arguments:[eventID,current.id]) {
                return try JSONDecoder().decode(SRSCard.self,from:Data(saved.utf8))
            }
            guard current == expected else { throw DomainError.invalidInput("This card has already changed. Reload the study session.") }
            let scheduled = try scheduler.review(current,rating:rating,now:now)
            try db.execute(sql:"UPDATE srsCard SET state=?,dueAt=?,stability=?,difficulty=?,repetitions=?,lapses=?,lastReviewedAt=?,schedulerVersion=?,learningStep=?,progress=? WHERE id=?",arguments:[scheduled.state.rawValue,scheduled.dueAt.timeIntervalSince1970,scheduled.stability,scheduled.difficulty,scheduled.repetitions,scheduled.lapses,now.timeIntervalSince1970,scheduled.schedulerVersion,scheduled.learningStep,scheduled.progress.rawValue,scheduled.id])
            // Date's reference-epoch representation may lose sub-microsecond precision
            // in SQLite's Unix-epoch Double. Return/log the stored snapshot so the
            // next repetition passes the same strict stale-write guard as a reload.
            guard let stored = try Row.fetchOne(db,sql:"SELECT * FROM srsCard WHERE id=?",arguments:[scheduled.id]) else { throw DomainError.missingRecord }
            let next = Self.card(stored)
            let before = String(decoding:try JSONEncoder().encode(current),as:UTF8.self), after = String(decoding:try JSONEncoder().encode(next),as:UTF8.self)
            try db.execute(sql:"INSERT INTO reviewLog(id,cardID,rating,reviewedAt,elapsedTime,scheduledInterval,priorState,resultingState,schedulerVersion,priorCardJSON,resultingCardJSON) VALUES(?,?,?,?,?,?,?,?,?,?,?)",arguments:[eventID,next.id,rating.rawValue,now.timeIntervalSince1970,elapsedTime,next.dueAt.timeIntervalSince(now),current.state.rawValue,next.state.rawValue,next.schedulerVersion,before,after])
            return next
        }
    }
    static func card(_ row: Row,idColumn:String="id") -> SRSCard {
        var value = SRSCard(id:row[idColumn],vocabularyItemID:row["vocabularyItemID"],dueAt:Date(timeIntervalSince1970:row["dueAt"]))
        value.state = CardState(rawValue:row["state"]) ?? .new
        value.stability=row["stability"]; value.difficulty=row["difficulty"]; value.repetitions=row["repetitions"]; value.lapses=row["lapses"]
        let time: Double? = row["lastReviewedAt"]; value.lastReviewedAt=time.map(Date.init(timeIntervalSince1970:))
        value.learningStep=row["learningStep"]; value.schedulerVersion=row["schedulerVersion"]
        value.progress=StudyProgress(rawValue:row["progress"]) ?? .studying
        return value
    }
}
