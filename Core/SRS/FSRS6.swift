import Foundation

public enum ReviewRating: Int, Codable, Sendable, CaseIterable { case again = 1, hard, good, easy }
public enum CardState: String, Codable, Sendable { case new, learning, review, relearning }
public enum StudyProgress: String, Codable, Sendable, CaseIterable { case forgotten, studying, learned }

public struct SRSCard: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var vocabularyItemID: String
    public var state: CardState = .new
    public var dueAt: Date
    public var stability: Double = 0
    public var difficulty: Double = 0
    public var repetitions: Int = 0
    public var lapses: Int = 0
    public var lastReviewedAt: Date?
    public var learningStep: Int = 0
    public var progress: StudyProgress = .studying
    public var schedulerVersion = "uninitialized"
    public init(id: String = UUID().uuidString, vocabularyItemID: String, dueAt: Date = .now) {
        self.id = id; self.vocabularyItemID = vocabularyItemID; self.dueAt = dueAt
    }
}

public struct StudyCard: Sendable, Identifiable, Equatable {
    public var id: String { card.id }
    public let card: SRSCard
    public let word: VocabularyItem
}

/// Swift port of py-fsrs 9446cb06605c597a063aeee49f7d188d42e34dc2 (MIT).
/// FSRS 6, default weights, learning 1m/10m, relearning 10m, deterministic (no fuzz).
public struct FSRS6: SRSScheduler {
    public static let version = "fsrs-6-py-9446cb0-no-fuzz"
    public static let parameters: [Double] = [0.212,1.2931,2.3065,8.2956,6.4133,0.8334,3.0194,0.001,1.8722,0.1666,0.796,1.4835,0.0614,0.2629,1.6483,0.6014,1.8729,0.5425,0.0912,0.0658,0.1542]
    public let desiredRetention: Double
    public init(desiredRetention: Double = 0.9) throws {
        guard desiredRetention.isFinite, (0.7...0.97).contains(desiredRetention) else { throw DomainError.invalidInput("Choose retention between 70% and 97%.") }
        self.desiredRetention = desiredRetention
    }
    public func review(_ original: SRSCard, rating: ReviewRating, now: Date) throws -> SRSCard {
        guard now.timeIntervalSince1970.isFinite, original.lastReviewedAt.map({ now >= $0 }) ?? true,
              original.stability.isFinite, original.difficulty.isFinite, original.stability >= 0,
              (0...10).contains(original.difficulty), original.learningStep >= 0 else {
            throw DomainError.invalidInput("Invalid review time or card memory state.")
        }
        let p = Self.parameters, g = Double(rating.rawValue)
        var card = original
        let days = original.lastReviewedAt.map { floor(now.timeIntervalSince($0) / 86_400) } ?? 0
        let s = original.stability, d = original.difficulty
        if original.repetitions == 0 || s == 0 || d == 0 {
            card.stability = p[rating.rawValue - 1]
            card.difficulty = clamp(p[4] - exp(p[5] * (g - 1)) + 1, 1, 10)
        } else {
            if days < 1 {
                var increase = exp(p[17] * (g - 3 + p[18])) * pow(s, -p[19])
                if rating != .again { increase = max(1, increase) }
                card.stability = s * increase
            } else {
                let r = retrievability(stability: s, elapsedDays: days)
                if rating == .again {
                    card.stability = min(p[11] * pow(d, -p[12]) * (pow(s + 1, p[13]) - 1) * exp((1-r) * p[14]), s / exp(p[17] * p[18]))
                } else {
                    card.stability = s * (1 + exp(p[8]) * (11-d) * pow(s, -p[9]) * (exp((1-r)*p[10])-1) * (rating == .hard ? p[15] : 1) * (rating == .easy ? p[16] : 1))
                }
            }
            card.stability = max(0.001, card.stability)
            let initialEasy = p[4] - exp(p[5] * 3) + 1
            let next = d + (10-d) * (-p[6] * (g-3)) / 9
            card.difficulty = clamp(p[7] * initialEasy + (1-p[7]) * next, 1, 10)
        }
        var interval: Double
        switch original.state {
        case .new, .learning, .relearning:
            let steps: [Double] = original.state == .relearning ? [600] : [60, 600]
            card.state = original.state == .new ? .learning : original.state
            if rating == .easy || (rating != .again && card.learningStep >= steps.count) {
                card.state = .review; card.learningStep = 0; interval = intervalDays(card.stability) * 86_400
            } else {
                switch rating {
                case .again: card.learningStep = 0; interval = steps[0]
                case .hard: interval = card.learningStep == 0 ? (steps.count == 1 ? steps[0]*1.5 : (steps[0]+steps[1])/2) : steps[card.learningStep]
                case .good:
                    if card.learningStep + 1 >= steps.count { card.state = .review; card.learningStep = 0; interval = intervalDays(card.stability)*86_400 }
                    else { card.learningStep += 1; interval = steps[card.learningStep] }
                case .easy: interval = intervalDays(card.stability)*86_400
                }
            }
        case .review:
            if rating == .again { card.state = .relearning; card.learningStep = 0; interval = 600; card.lapses += 1 }
            else { interval = intervalDays(card.stability) * 86_400 }
        }
        guard card.stability.isFinite, interval.isFinite else { throw DomainError.invalidInput("The review exceeds the scheduler's numeric bounds.") }
        card.progress = rating == .again ? .forgotten : (card.state == .review ? .learned : .studying)
        card.dueAt = now.addingTimeInterval(interval); card.lastReviewedAt = now
        card.repetitions += 1; card.schedulerVersion = Self.version
        return card
    }
    public func retrievability(stability: Double, elapsedDays: Double) -> Double {
        guard stability > 0 else { return 0 }
        let decay = -Self.parameters[20], factor = pow(0.9, 1/decay)-1
        return pow(1 + factor * max(0, elapsedDays)/stability, decay)
    }
    private func intervalDays(_ stability: Double) -> Double {
        let decay = -Self.parameters[20], factor = pow(0.9, 1/decay)-1
        return clamp((stability/factor * (pow(desiredRetention,1/decay)-1)).rounded(.toNearestOrEven), 1, 36_500)
    }
    private func clamp(_ n: Double, _ low: Double, _ high: Double) -> Double { min(high, max(low, n)) }
}
