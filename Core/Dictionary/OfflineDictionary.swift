import Foundation
import GRDB

public enum DictionaryRecordKind:String,Sendable,Codable { case entry,lexeme,root }
public struct DictionaryRecord:Identifiable,Sendable,Equatable {
    public var id:String { language+":"+kind.rawValue+":"+sourceID }
    public let language:String
    public let kind:DictionaryRecordKind
    public let sourceID,headword,english,partOfSpeech,definition,transliteration:String
}
public struct DictionaryPack:Identifiable,Sendable {
    public var id:String { metadata.languageCode }
    public let metadata:LanguagePackMetadata
    public let entries,lexemes,roots,forms:Int
}
public struct DictionaryTranslationGroup: Identifiable, Sendable {
    public var id:String { pack.id }
    public let pack:DictionaryPack
    public let records:[DictionaryRecord]
    public let hasMore:Bool
}
public struct VocabularyDictionaryInspection: Sendable {
    public let exact:DictionaryRecord?
    public let candidates:[DictionaryRecord]
}
public struct DictionaryPage:Sendable { public let records:[DictionaryRecord];public let hasMore:Bool }
public struct DictionaryDetail:Sendable {
    public let record:DictionaryRecord
    public let translations:[String]
    public let senseID,etymology:String
    public let rootID,lexemeID:String?
    public let sources:[String:String]
    public func vocabularyDraft(target:String) -> VocabularyDraft {
        let reference:SemiticVocabularyReference?
        if SemiticLanguage(rawValue:record.language) != nil && (rootID != nil || lexemeID != nil) {
            reference = .init(languageCode:record.language,kind:record.kind == .root ? .root : .lexeme,rootID:rootID,lexemeID:lexemeID)
        } else { reference=nil }
        return .init(englishLemma:String(record.english.prefix(400)),targetLanguage:record.language,targetLemma:target,targetSurface:target,senseID:senseID,partOfSpeech:record.partOfSpeech,lexicalReference:reference)
    }
}
public struct DictionaryForm:Identifiable,Sendable {
    public let id,surface,analysis,transliteration,source:String
    public let lexicalReference:SemiticVocabularyReference?
}
public struct DictionaryFormPage:Sendable { public let forms:[DictionaryForm];public let hasMore:Bool }

/// Read-only search index plus the original bundled databases. Search is paginated and never
/// depends on the enabled replacement languages, the LLM, or the user's saved vocabulary.
public actor OfflineDictionary {
    private let indexes:[DatabaseQueue]
    private let availablePacks:[DictionaryPack]
    private let packDirectories:[String:URL]
    private var sources:[String:DatabaseQueue]=[:]
    public init(directory:URL,additionalDirectories:[URL]=[]) throws {
        var config=Configuration();config.readonly=true
        var queues:[DatabaseQueue]=[],packs:[DictionaryPack]=[],locations:[String:URL]=[:]
        for folder in [directory]+additionalDirectories {
            let queue=try DatabaseQueue(path:folder.appendingPathComponent("_dictionary/search.sqlite").path,configuration:config)
            let found=try queue.read { db in
                try Row.fetchAll(db,sql:"SELECT * FROM pack ORDER BY language").map { row in
                    let meta=try JSONDecoder().decode(LanguagePackMetadata.self,from:Data((row["metadata"] as String).utf8))
                    return DictionaryPack(metadata:meta,entries:row["entryCount"],lexemes:row["lexemeCount"],roots:row["rootCount"],forms:row["formCount"])
                }
            }
            for pack in found {
                guard locations[pack.id] == nil else { throw DomainError.invalidInput("Duplicate dictionary language.") }
                locations[pack.id]=folder
            }
            queues.append(queue);packs+=found
        }
        indexes=queues;availablePacks=packs.sorted { $0.id < $1.id };packDirectories=locations
    }
    public static func key(_ text:String) -> String { SemiticUnicode.key(text).replacingOccurrences(of:"ß",with:"ss") }
    public func packs() -> [DictionaryPack] { availablePacks }
    private func source(_ language:String) throws -> DatabaseQueue {
        if let existing=sources[language] { return existing }
        guard let pack=availablePacks.first(where: { $0.id == language }),let folder=packDirectories[language],
              pack.metadata.lexiconDatabaseName == URL(fileURLWithPath:pack.metadata.lexiconDatabaseName).lastPathComponent else { throw DomainError.missingRecord }
        var config=Configuration();config.readonly=true
        let queue=try DatabaseQueue(path:folder.appendingPathComponent(pack.metadata.lexiconDatabaseName).path,configuration:config)
        sources[language]=queue;return queue
    }
    /// Every installed language gets its own bounded result set, even when that language is
    /// disabled for reading. Homonyms keep separate senses and missing coverage stays explicit.
    public func englishTranslations(_ text:String,limitPerLanguage:Int=12) throws -> [DictionaryTranslationGroup] {
        try Task.checkCancellation()
        guard text.count<=200 else { throw DomainError.invalidInput("Use a shorter English expression.") }
        let clean=Self.key(text.trimmingCharacters(in:.whitespacesAndNewlines)),size=max(1,min(limitPerLanguage,100))
        return try availablePacks.map { pack in
            let rows=try indexes.flatMap { index in
                try index.read { db in
                    try Row.fetchAll(db,sql:"SELECT * FROM document WHERE language=? AND kind='entry' AND englishKey=? ORDER BY pos,id LIMIT ?",arguments:[pack.id,clean,size+1]).map(Self.record)
                }
            }
            return .init(pack:pack,records:Array(rows.prefix(size)),hasMore:rows.count>size)
        }
    }
    public func search(_ text:String,language:String?=nil,offset:Int=0,limit:Int=50) throws -> DictionaryPage {
        try Task.checkCancellation()
        guard text.count <= 200,offset >= 0 else { throw DomainError.invalidInput("Use a shorter dictionary query.") }
        let clean=Self.key(text.trimmingCharacters(in:.whitespacesAndNewlines)),size=max(1,min(limit,100))
        let tokens=clean.split { !$0.isLetter && !$0.isNumber }
        if !clean.isEmpty && tokens.isEmpty { return .init(records:[],hasMore:false) }
        // Values go through parameters; FTS operators and punctuation never become query syntax.
        let match=tokens.prefix(12).map { "\"\($0)\"*" }.joined(separator:" AND ")
        var native:[String:[String]]=[:]
        if !clean.isEmpty {
            for pack in packs() where (language == nil || language == pack.id) && SemiticLanguage(rawValue:pack.id) != nil && SemiticUnicode.scriptMatches(clean,language:pack.id) {
                native[pack.id]=try source(pack.id).read { try String.fetchAll($0,sql:"SELECT DISTINCT lexemeID FROM semForm WHERE normalized=? LIMIT 128",arguments:[clean]) }
            }
        }
        let nativeMatches=native
        func page(_ index:DatabaseQueue,_ start:Int) throws -> [Row] {
          try index.read { db in
            var args:StatementArguments=[]
            let rank=clean.isEmpty ? "0" : "CASE WHEN d.englishKey=? THEN 0 WHEN d.id IN (SELECT documentID FROM target WHERE key=?) THEN 1 ELSE 2 END"
            if !clean.isEmpty {args += [clean,clean]}
            var sql="SELECT d.*, \(rank) AS matchRank FROM document d WHERE 1=1"
            if let language { sql += " AND d.language=?";args += [language] }
            if !clean.isEmpty {
                var choices=["d.id IN (SELECT rowid FROM search WHERE search MATCH ?)","d.id IN (SELECT documentID FROM target WHERE key=?)","d.id IN (SELECT t.documentID FROM target t JOIN nativeForm f ON f.lemmaKey=t.key JOIN document nd ON nd.id=t.documentID AND nd.language=f.language WHERE f.key=?)"]
                args += [match,clean,clean]
                for code in nativeMatches.keys.sorted() {
                    let ids=nativeMatches[code]!
                    if !ids.isEmpty {
                        choices.append("(d.language=? AND d.kind='lexeme' AND d.sourceID IN (\(Array(repeating:"?",count:ids.count).joined(separator:","))))")
                        args += [code];args += StatementArguments(ids)
                    }
                }
                sql += " AND ("+choices.joined(separator:" OR ")+")"
                sql += " ORDER BY matchRank,d.language,d.englishKey,d.id"
            } else { sql += " ORDER BY d.language,d.englishKey,d.id" }
            sql += " LIMIT ? OFFSET ?";args += [size+1,start]
            return try Row.fetchAll(db,sql:sql,arguments:args)
          }
        }
        // Merge bounded pages from the bundled index and imported add-ons. Only one page
        // per index is resident, including when the caller browses far into the dictionary.
        var pages=try indexes.map { try page($0,0) },positions=Array(repeating:0,count:indexes.count),starts=Array(repeating:0,count:indexes.count)
        var skipped=0,rows:[DictionaryRecord]=[]
        func precedes(_ a:Row,_ b:Row)->Bool {
            let ar:Int=a["matchRank"],br:Int=b["matchRank"]
            if ar != br { return ar<br }
            let al:String=a["language"],bl:String=b["language"]
            if al != bl { return al<bl }
            let ak:String=a["englishKey"],bk:String=b["englishKey"]
            if ak != bk { return ak<bk }
            return (a["id"] as Int64)<(b["id"] as Int64)
        }
        while rows.count<size+1 {
            try Task.checkCancellation()
            let candidates=indexes.indices.filter { positions[$0]<pages[$0].count }
            guard let chosen=candidates.min(by:{precedes(pages[$0][positions[$0]],pages[$1][positions[$1]])}) else { break }
            let row=pages[chosen][positions[chosen]];positions[chosen]+=1
            if skipped<offset { skipped+=1 } else { rows.append(Self.record(row)) }
            if positions[chosen]==pages[chosen].count && pages[chosen].count==size+1 {
                starts[chosen]+=pages[chosen].count;pages[chosen]=try page(indexes[chosen],starts[chosen]);positions[chosen]=0
            }
        }
        return .init(records:Array(rows.prefix(size)),hasMore:rows.count > size)
    }
    public func detail(_ record:DictionaryRecord) throws -> DictionaryDetail {
        try source(record.language).read { db in
            switch record.kind {
            case .entry:
                guard let row=try Row.fetchOne(db,sql:"SELECT * FROM entry WHERE rowid=?",arguments:[record.sourceID]) else { throw DomainError.missingRecord }
                let targets=try JSONDecoder().decode([String].self,from:Data((row["translations"] as String).utf8))
                let provenance=try JSONDecoder().decode([String:String].self,from:Data((row["provenance"] as String).utf8))
                let sense:String=row["senseID"]
                let lexical=SemiticLanguage(rawValue:record.language) == nil ? nil : try Row.fetchOne(db,sql:"SELECT * FROM semLexeme WHERE id=?",arguments:[sense])
                return .init(record:record,translations:targets,senseID:sense,etymology:lexical?["etymology"] ?? "",rootID:lexical?["rootID"],lexemeID:lexical == nil ? nil : sense,sources:provenance)
            case .lexeme:
                guard let row=try Row.fetchOne(db,sql:"SELECT * FROM semLexeme WHERE id=?",arguments:[record.sourceID]) else { throw DomainError.missingRecord }
                return .init(record:record,translations:[row["lemma"]],senseID:record.sourceID,etymology:row["etymology"],rootID:row["rootID"],lexemeID:record.sourceID,sources:["url":row["source"]])
            case .root:
                guard let row=try Row.fetchOne(db,sql:"SELECT * FROM semRoot WHERE id=?",arguments:[record.sourceID]) else { throw DomainError.missingRecord }
                return .init(record:record,translations:[row["native"]],senseID:"root:"+record.sourceID,etymology:row["etymology"],rootID:record.sourceID,lexemeID:nil,sources:["url":row["source"]])
            }
        }
    }
    public func meaning(for word:VocabularyDraft) throws -> String? {
        try source(word.targetLanguage).read { db in
            if let reference=word.lexicalReference {
                if reference.kind == .root,let id=reference.rootID {
                    return try String.fetchOne(db,sql:"SELECT meaning FROM semRoot WHERE id=?",arguments:[id])
                }
                if let id=reference.lexemeID {return try String.fetchOne(db,sql:"SELECT gloss FROM semLexeme WHERE id=?",arguments:[id])}
            }
            return try String.fetchOne(db,sql:"SELECT definition FROM entry WHERE lemma=? AND senseID=? LIMIT 1",arguments:[word.englishLemma.lowercased(),word.senseID])
        }
    }
    /// Prefer the saved lexical identity. Model/manual cards without one show possible
    /// dictionary senses instead of silently attributing an arbitrary sense to the card.
    public func inspect(_ word:VocabularyDraft) throws -> VocabularyDictionaryInspection {
        guard availablePacks.contains(where:{$0.id==word.targetLanguage}) else {return .init(exact:nil,candidates:[])}
        let kind:DictionaryRecordKind
        let identifier:String?
        if let reference=word.lexicalReference {
            kind=reference.kind == .root ? .root:.lexeme
            identifier=reference.kind == .root ? reference.rootID:reference.lexemeID
        } else {
            kind = .entry
            identifier=try source(word.targetLanguage).read { db in
                try String.fetchOne(db,sql:"SELECT CAST(rowid AS TEXT) FROM entry WHERE senseID=? AND lemma=? ORDER BY rowid LIMIT 1",arguments:[word.senseID,word.englishLemma.lowercased()])
            }
        }
        if let identifier {
            for index in indexes {
                if let exact=try index.read({ db in
                    try Row.fetchOne(db,sql:"SELECT * FROM document WHERE language=? AND kind=? AND sourceID=? LIMIT 1",arguments:[word.targetLanguage,kind.rawValue,identifier]).map(Self.record)
                }) {return .init(exact:exact,candidates:[exact])}
            }
        }
        let english=try englishTranslations(word.englishLemma,limitPerLanguage:100).first{$0.id==word.targetLanguage}?.records ?? []
        let keys=Set([Self.key(word.targetLemma),Self.key(word.targetSurface)])
        var matches:[DictionaryRecord]=[]
        for record in english where record.partOfSpeech==word.partOfSpeech || word.partOfSpeech=="unknown" {
            if try detail(record).translations.contains(where:{keys.contains(Self.key($0))}) {matches.append(record)}
        }
        if matches.isEmpty {
            matches=try search(word.targetSurface,language:word.targetLanguage,limit:50).records
                .filter { $0.kind != .root }
        }
        return .init(exact:nil,candidates:matches)
    }
    public func forms(_ detail:DictionaryDetail,target:String,offset:Int=0,limit:Int=50) throws -> DictionaryFormPage {
        let size=max(1,min(limit,100))
        guard offset >= 0 else { throw DomainError.invalidInput("Invalid dictionary page.") }
        let forms=try source(detail.record.language).read { db -> [DictionaryForm] in
            if SemiticLanguage(rawValue:detail.record.language) != nil {
                let column=detail.record.kind == .root ? "rootID" : "lexemeID"
                guard let id=detail.record.kind == .root ? detail.rootID : detail.lexemeID else { return [] }
                return try Row.fetchAll(db,sql:"SELECT * FROM semForm WHERE \(column)=? ORDER BY id LIMIT ? OFFSET ?",arguments:[id,size+1,offset]).map { row in
                    let tags=try JSONDecoder().decode([String].self,from:Data((row["tags"] as String).utf8))
                    let ref=SemiticVocabularyReference(languageCode:detail.record.language,kind:.wordForm,rootID:row["rootID"],lexemeID:row["lexemeID"],wordFormID:row["id"])
                    return .init(id:row["id"],surface:row["surface"],analysis:tags.joined(separator:" · "),transliteration:row["transliteration"],source:row["source"],lexicalReference:ref)
                }
            }
            let lemma=target.replacingOccurrences(of:"\u{301}",with:"").precomposedStringWithCanonicalMapping.lowercased()
            var queries:[String]=[],arguments:StatementArguments=[]
            if try db.tableExists("lexicalForm") {
                queries.append("SELECT 'lexical:'||rowid AS ident,surface,tags AS analysis,source FROM lexicalForm WHERE lemmaKey=?");arguments += [Self.key(target)]
            }
            if try db.tableExists("nounForm") {
                queries.append("SELECT 'noun:'||rowid AS ident,surface,coalesce(number,'')||' · '||coalesce(gender,'') AS analysis,source FROM nounForm WHERE lemma=?");arguments += [lemma]
            }
            if try db.tableExists("caseForm") {
                queries.append("SELECT 'case:'||rowid AS ident,surface,coalesce(number,'')||' · '||coalesce(grammaticalCase,'')||' · '||coalesce(gender,'') AS analysis,source FROM caseForm WHERE lemma=?");arguments += [lemma]
            }
            if try db.tableExists("practiceForm") {
                queries.append("SELECT 'practice:'||rowid AS ident,surface,coalesce(form,'')||' · '||coalesce(tense,'')||' · '||coalesce(person,'')||' · '||coalesce(number,'')||' · '||coalesce(gender,'') AS analysis,source FROM practiceForm WHERE lemma=?");arguments += [lemma]
            }
            guard !queries.isEmpty else { return [] }
            let sql=queries.joined(separator:" UNION ALL ")+" ORDER BY ident LIMIT ? OFFSET ?";arguments += [size+1,offset]
            return try Row.fetchAll(db,sql:sql,arguments:arguments).map { row in
                .init(id:row["ident"],surface:row["surface"],analysis:row["analysis"],transliteration:"",source:row["source"],lexicalReference:nil)
            }
        }
        return .init(forms:Array(forms.prefix(size)),hasMore:forms.count > size)
    }
    private static func record(_ r:Row) -> DictionaryRecord {
        .init(language:r["language"],kind:DictionaryRecordKind(rawValue:r["kind"])!,sourceID:r["sourceID"],headword:r["headword"],english:r["english"],partOfSpeech:r["pos"],definition:r["definition"],transliteration:r["transliteration"])
    }
}
