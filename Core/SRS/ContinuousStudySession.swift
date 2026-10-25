import Foundation

/// A fixed selection with no completion gate. FSRS owns due dates; this queue only
/// selects the next card, permitting early practice when nothing is due.
public struct ContinuousStudySession: Sendable {
    private var cards: [String: StudyCard] = [:]
    private var order: [String: Int] = [:]
    private var appearances: [String: Int] = [:]
    private var currentID: String?
    public private(set) var reviewCount = 0
    public var current: StudyCard? { currentID.flatMap { cards[$0] } }
    public var count: Int { cards.count }

    public init(cards selection: [StudyCard], now: Date = .now) {
        for card in selection where cards[card.id] == nil {
            order[card.id] = order.count
            cards[card.id] = card
        }
        currentID = next(now: now, excluding: nil)
    }

    /// Accept only the transaction's updated snapshot, never the stale input card.
    public mutating func record(_ updated: SRSCard, now: Date = .now) throws {
        guard let current, updated.id == current.id,
              updated.vocabularyItemID == current.word.id,
              updated.repetitions == current.card.repetitions + 1 else {
            throw DomainError.invalidInput("The review does not match the displayed card.")
        }
        let word = VocabularyItem(id: current.word.id, draft: current.word.draft,
                                  createdAt: current.word.createdAt, studyProgress: updated.progress)
        cards[updated.id] = StudyCard(card: updated, word: word)
        appearances[updated.id, default: 0] += 1
        reviewCount += 1
        currentID = next(now: now, excluding: updated.id)
    }

    /// Recover from external edits/deletions without admitting words outside the selection.
    public mutating func reconcile(_ available: [StudyCard], now: Date = .now) {
        let selected = Set(cards.keys)
        cards = Dictionary(available.filter { selected.contains($0.id) }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if currentID.flatMap({ cards[$0] }) == nil { currentID = next(now: now, excluding: nil) }
    }

    private func next(now: Date, excluding lastID: String?) -> String? {
        let candidates = cards.values.filter { cards.count == 1 || $0.id != lastID }
        func earlier(_ a: StudyCard, _ b: StudyCard) -> Bool {
            if a.card.dueAt != b.card.dueAt { return a.card.dueAt < b.card.dueAt }
            return order[a.id, default: 0] < order[b.id, default: 0]
        }
        // Due learning/relearning steps take precedence over due mature cards.
        let learning = candidates.filter { [.learning, .relearning].contains($0.card.state) && $0.card.dueAt <= now }
        if let card = learning.min(by: earlier) { return card.id }
        let due = candidates.filter { $0.card.state != .new && $0.card.dueAt <= now }
        if let card = due.min(by: earlier) { return card.id }
        // Cover the whole chosen selection before early repeats. Afterwards, balance
        // exposure, using actual FSRS due dates as the tie breaker. Time is never faked.
        return candidates.min { a, b in
            let ac = appearances[a.id, default: 0], bc = appearances[b.id, default: 0]
            return ac != bc ? ac < bc : earlier(a, b)
        }?.id
    }
}
