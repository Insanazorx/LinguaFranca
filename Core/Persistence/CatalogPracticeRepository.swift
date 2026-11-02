import Foundation
import GRDB

extension DatabaseManager {
    public func catalogStats(source: CatalogPracticeSource) async throws -> CatalogPracticeStats {
        try await queue.read { db in
            let r=try Row.fetchOne(db,sql:"SELECT coalesce(sum(points),0) points,coalesce(sum(answers),0) answers,coalesce(max(bestCombo),0) combo,coalesce(max(points),0) best FROM catalogRound WHERE source=?",arguments:[source.rawValue])!
            return .init(points:r["points"],answers:r["answers"],bestCombo:r["combo"],bestRound:r["best"])
        }
    }
    public func dueCatalogFamilies(source: CatalogPracticeSource, now: Date = .now) async throws -> [String] {
        try await queue.read { try String.fetchAll($0,sql:"SELECT familyID FROM catalogCard WHERE source=? AND dueAt<=? ORDER BY dueAt,id LIMIT 128",arguments:[source.rawValue,now.timeIntervalSince1970]) }
    }
    public func dueCatalogQuestions(source: CatalogPracticeSource, now: Date = .now) async throws -> [CatalogQuestion] {
        try await queue.read { db in
            try String.fetchAll(db,sql:"SELECT questionJSON FROM catalogCard WHERE source=? AND dueAt<=? ORDER BY dueAt,id LIMIT 128",arguments:[source.rawValue,now.timeIntervalSince1970])
                .map {try JSONDecoder().decode(CatalogQuestion.self,from:Data($0.utf8))}
        }
    }
    public func startCatalogPractice(_ questions: [CatalogQuestion], source: CatalogPracticeSource, now: Date = .now) async throws -> CatalogPracticeStart {
        guard !questions.isEmpty, questions.count<=100,questions.allSatisfy({$0.source==source && !$0.word.isEmpty && !$0.meaning.isEmpty}),Set(questions.map(\.id)).count==questions.count else { throw DomainError.invalidInput("No suitable words in this selection. Try a broader filter.") }
        return try await queue.write { db in
            let score=CatalogScore(sessionID:UUID().uuidString)
            try db.execute(sql:"INSERT INTO catalogRound(id,source,startedAt,scoreJSON,points,answers,bestCombo) VALUES(?,?,?,?,0,0,0)",arguments:[score.sessionID,source.rawValue,now.timeIntervalSince1970,try Self.catalogJSON(score)])
            var cards:[CatalogPracticeCard]=[]
            for question in questions {
                let card:SRSCard
                if let json=try String.fetchOne(db,sql:"SELECT cardJSON FROM catalogCard WHERE id=? AND source=?",arguments:[question.id,source.rawValue]) {
                    card=try JSONDecoder().decode(SRSCard.self,from:Data(json.utf8))
                } else {
                    card=SRSCard(id:question.id,vocabularyItemID:question.id,dueAt:now)
                    try db.execute(sql:"INSERT INTO catalogCard(id,source,familyID,questionJSON,cardJSON,dueAt) VALUES(?,?,?,?,?,?)",arguments:[question.id,source.rawValue,question.familyID,try Self.catalogJSON(question),try Self.catalogJSON(card),card.dueAt.timeIntervalSince1970])
                }
                try db.execute(sql:"INSERT INTO catalogRoundCard VALUES(?,?)",arguments:[score.sessionID,question.id])
                cards.append(.init(question:question,card:card))
            }
            return .init(cards:cards,score:score)
        }
    }
    public func reviewCatalogCard(_ expected: SRSCard, question: CatalogQuestion, sessionID: String,
                                  rating: ReviewRating, usedContext: Bool, now: Date = .now, eventID: String = UUID().uuidString) async throws -> CatalogReviewResult {
        let scheduler=try FSRS6()
        return try await queue.write { db in
            if let json=try String.fetchOne(db,sql:"SELECT resultJSON FROM catalogReview WHERE id=? AND sessionID=? AND questionID=?",arguments:[eventID,sessionID,question.id]) {
                return try JSONDecoder().decode(CatalogReviewResult.self,from:Data(json.utf8))
            }
            guard question.id==expected.id, expected.vocabularyItemID==question.id,
                  let row=try Row.fetchOne(db,sql:"SELECT * FROM catalogCard WHERE id=? AND source=?",arguments:[question.id,question.source.rawValue]),
                  let round=try Row.fetchOne(db,sql:"SELECT * FROM catalogRound WHERE id=? AND source=? AND endedAt IS NULL AND EXISTS(SELECT 1 FROM catalogRoundCard m WHERE m.sessionID=catalogRound.id AND m.questionID=?)",arguments:[sessionID,question.source.rawValue,question.id]) else { throw DomainError.missingRecord }
            let current=try JSONDecoder().decode(SRSCard.self,from:Data((row["cardJSON"] as String).utf8))
            guard current==expected else { throw DomainError.invalidInput("This answer was already recorded.") }
            let next=try scheduler.review(current,rating:rating,now:now)
            var score=try JSONDecoder().decode(CatalogScore.self,from:Data((round["scoreJSON"] as String).utf8))
            score.record(recalled:rating != .again,context:usedContext && question.context != nil)
            let result=CatalogReviewResult(card:next,score:score)
            try db.execute(sql:"UPDATE catalogCard SET cardJSON=?,dueAt=? WHERE id=?",arguments:[try Self.catalogJSON(next),next.dueAt.timeIntervalSince1970,next.id])
            try db.execute(sql:"UPDATE catalogRound SET scoreJSON=?,points=?,answers=?,bestCombo=? WHERE id=?",arguments:[try Self.catalogJSON(score),score.points,score.answers,score.bestCombo,sessionID])
            try db.execute(sql:"INSERT INTO catalogReview(id,sessionID,questionID,reviewedAt,rating,priorCardJSON,resultJSON) VALUES(?,?,?,?,?,?,?)",arguments:[eventID,sessionID,question.id,now.timeIntervalSince1970,rating.rawValue,try Self.catalogJSON(current),try Self.catalogJSON(result)])
            return result
        }
    }
    public func endCatalogPractice(sessionID: String, now: Date = .now) async throws {
        try await queue.write { try $0.execute(sql:"UPDATE catalogRound SET endedAt=coalesce(endedAt,?) WHERE id=?",arguments:[now.timeIntervalSince1970,sessionID]) }
    }
    private static func catalogJSON<T: Encodable>(_ value:T) throws -> String { String(decoding:try JSONEncoder().encode(value),as:UTF8.self) }
}
