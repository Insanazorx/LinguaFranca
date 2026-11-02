import Foundation

public enum CatalogPracticeSource: String, Codable, Sendable { case latin, semitic }
public struct CatalogPracticePeer: Codable, Sendable, Equatable {
    public let language, word, meaning: String
}
public struct CatalogContext: Codable, Sendable, Equatable {
    public let before, after, english: String
    public var original: String { before + english + after }
}
public struct CatalogQuestion: Codable, Sendable, Equatable, Identifiable {
    public let id, familyID, familyTitle, language, word, meaning, partOfSpeech, transliteration, sourceID, pattern: String
    public let source: CatalogPracticeSource
    public let context: CatalogContext?
    public let peers: [CatalogPracticePeer]
    public var dictionaryRecord: DictionaryRecord {
        .init(language:language,kind:source == .latin ? .entry : .lexeme,sourceID:sourceID,headword:word,english:meaning,partOfSpeech:partOfSpeech,definition:meaning,transliteration:transliteration)
    }
    public init(id:String,familyID:String,familyTitle:String,language:String,word:String,meaning:String,partOfSpeech:String,
                transliteration:String="",sourceID:String,pattern:String="",source:CatalogPracticeSource,context:CatalogContext?=nil,peers:[CatalogPracticePeer]=[]) {
        self.id=id;self.familyID=familyID;self.familyTitle=familyTitle;self.language=language;self.word=word;self.meaning=meaning
        self.partOfSpeech=partOfSpeech;self.transliteration=transliteration;self.sourceID=sourceID;self.pattern=pattern
        self.source=source;self.context=context;self.peers=peers
    }
}
public struct CatalogPracticeCard: Sendable, Identifiable {
    public var id: String { question.id }
    public let question: CatalogQuestion
    public let card: SRSCard
}
public struct CatalogScore: Codable, Sendable, Equatable {
    public let sessionID: String
    public var points = 0, combo = 0, bestCombo = 0, answers = 0, recalled = 0
    public init(sessionID: String) { self.sessionID=sessionID }
    public mutating func record(recalled: Bool, context: Bool) {
        answers += 1
        if recalled {
            self.recalled += 1; combo += 1; bestCombo=max(bestCombo,combo)
            points += 10 + min(40,(combo/3)*10) + (context ? 5 : 0)
        } else { combo=0 }
    }
}
public struct CatalogReviewResult: Codable, Sendable {
    public let card: SRSCard
    public let score: CatalogScore
}
public struct CatalogPracticeStart: Sendable {
    public let cards: [CatalogPracticeCard]
    public let score: CatalogScore
}
public struct CatalogPracticeStats: Sendable {
    public let points, answers, bestCombo, bestRound: Int
}

/// Random mini-selections, with due families admitted first. No text/model work here.
enum CatalogSampling {
    static func families(_ all: [String], preferred: [String], contextFamilies: [String] = [], limit: Int, rng: inout SeededGenerator) -> [String] {
        let eligible=Set(all), size=max(1,min(limit,24))
        var due=Array(Set(preferred).intersection(eligible)).sorted();due.shuffle(using:&rng)
        var contexts=Array(Set(contextFamilies).intersection(eligible)).sorted();contexts.shuffle(using:&rng)
        var selected=Array(contexts.prefix(1))
        selected += due.filter{!selected.contains($0)}.prefix(min(max(1,size/2),size-selected.count))
        var rest=all.filter{!selected.contains($0)};rest.shuffle(using:&rng)
        selected += rest.prefix(max(0,size-selected.count));return selected
    }
}

/// Hand-authored English scaffolds, used only with an exact dictionary sense.
/// Nominal citation forms avoid inventing Semitic inflections in English syntax.
public enum CatalogContexts {
    public static func make(english: String, pos: String) -> CatalogContext? {
        guard pos == "noun" else { return nil }
        let key=english.lowercased().trimmingCharacters(in:.whitespacesAndNewlines)

        guard let parts=templates[key] else { return nil }
        return .init(before:parts.0,after:parts.1,english:key)
    }
    static var concepts: [String] { templates.keys.sorted() }
    private static let templates: [String:(String,String)] = [
            "book":("I opened the "," and read the next chapter."),
            "dog":("The "," wagged its tail when its owner came home."),
            "cat":("The "," purred softly beside the window."),
            "water":("After the long walk, she drank some cold ","."),
            "house":("We unlocked the front door of the "," and went inside."),
            "bread":("He sliced the fresh "," and spread butter on it."),
            "milk":("She poured some "," into her coffee."),
            "sun":("The "," rose above the hills and warmed the fields."),
            "moon":("At night, the "," shone above the sleeping town."),
            "hand":("He raised his "," and waved hello."),
            "eye":("Dust got into my ",", so I blinked several times."),
            "door":("Someone knocked on the ",", and I went to let them in."),
            "king":("The "," wore a crown and ruled the kingdom."),
            "peace":("After years of fighting, both sides finally agreed to ","."),
            "night":("The streets grew dark as "," fell."),
            "sea":("The boat sailed across the "," toward the distant shore."),
            "letter":("She put the "," in an envelope and posted it."),
            "tree":("Birds built a nest in the tall ","."),
            "flower":("A bee landed on the "," to collect nectar."),
            "garden":("She planted vegetables in the "," behind her house."),
            "friend":("My "," listened carefully when I needed someone to talk to.")
        ]

    static func semitic(meaning: String, pos: String) -> CatalogContext? {
        // Only exact first senses; never match an arbitrary substring in a long definition.
        let first=meaning.split(separator:";").first.map(String.init)?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
        return make(english:first,pos:pos)
    }
}

/// Session-local selection ordering; persisted cards are scheduled by the existing FSRS 6.
public struct CatalogPracticeQueue: Sendable {
    private var cards: [CatalogPracticeCard]
    private var exposures: [String:Int] = [:]
    public private(set) var current: CatalogPracticeCard?
    public private(set) var reviews=0
    public var count: Int { cards.count }
    public init(cards: [CatalogPracticeCard], now: Date = .now) {
        var seen=Set<String>();self.cards=cards.filter{seen.insert($0.id).inserted}
        current=choose(now:now,excluding:nil)
    }
    public mutating func record(_ updated: SRSCard, now: Date = .now) throws {
        guard let current, current.card.id==updated.id, updated.repetitions==current.card.repetitions+1,
              let index=cards.firstIndex(where:{$0.id==current.id}) else { throw DomainError.invalidInput("This practice card changed. Reopen the round.") }
        cards[index] = .init(question:current.question,card:updated)
        exposures[current.id,default:0] += 1;reviews += 1
        self.current=choose(now:now,excluding:current.id)
    }
    private func choose(now: Date, excluding id: String?) -> CatalogPracticeCard? {
        cards.enumerated().filter{cards.count==1 || $0.element.id != id}.min { a,b in
            let ad=a.element.card.dueAt<=now && a.element.card.state != .new
            let bd=b.element.card.dueAt<=now && b.element.card.state != .new
            if ad != bd { return ad }
            let ae=exposures[a.element.id,default:0],be=exposures[b.element.id,default:0]
            if ae != be { return ae<be }
            if ad && a.element.card.dueAt != b.element.card.dueAt { return a.element.card.dueAt<b.element.card.dueAt }
            return a.offset<b.offset
        }?.element
    }
}
