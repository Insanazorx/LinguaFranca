import Foundation
import GRDB

public enum DictionaryRecordKind:String,Sendable,Codable { case entry,lexeme,root }
public struct DictionaryRecord:Identifiable,Sendable,Equatable {
    public let id:Int64
    public let language:String
    public let kind:DictionaryRecordKind
    public let sourceID,headword,english,partOfSpeech,definition,transliteration:String
}
public struct DictionaryPack:Identifiable,Sendable {
    public var id:String { metadata.languageCode }
    public let metadata:LanguagePackMetadata
    public let entries,lexemes,roots,forms:Int
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
    private let index:DatabaseQueue
    private let directory:URL
    private var sources:[String:DatabaseQueue]=[:]
    public init(directory:URL) throws {
        self.directory=directory
        var config=Configuration();config.readonly=true
        index=try DatabaseQueue(path:directory.appendingPathComponent("_dictionary/search.sqlite").path,configuration:config)
    }
    public static func key(_ text:String) -> String { SemiticUnicode.key(text).replacingOccurrences(of:"ß",with:"ss") }
    public func packs() throws -> [DictionaryPack] {
        try index.read { db in
            try Row.fetchAll(db,sql:"SELECT * FROM pack ORDER BY language").map { row in
                let meta=try JSONDecoder().decode(LanguagePackMetadata.self,from:Data((row["metadata"] as String).utf8))
                return .init(metadata:meta,entries:row["entryCount"],lexemes:row["lexemeCount"],roots:row["rootCount"],forms:row["formCount"])
            }
        }
    }
    private func source(_ language:String) throws -> DatabaseQueue {
        if let existing=sources[language] { return existing }
        guard let pack=try packs().first(where: { $0.id == language }) else { throw DomainError.missingRecord }
        var config=Configuration();config.readonly=true
        let queue=try DatabaseQueue(path:directory.appendingPathComponent(pack.metadata.lexiconDatabaseName).path,configuration:config)
        sources[language]=queue;return queue
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
            for pack in try packs() where (language == nil || language == pack.id) && SemiticLanguage(rawValue:pack.id) != nil && SemiticUnicode.scriptMatches(clean,language:pack.id) {
                native[pack.id]=try source(pack.id).read { try String.fetchAll($0,sql:"SELECT DISTINCT lexemeID FROM semForm WHERE normalized=? LIMIT 128",arguments:[clean]) }
            }
        }
        let rows=try index.read { db in
            var sql="SELECT d.* FROM document d WHERE 1=1",args:StatementArguments=[]
            if let language { sql += " AND d.language=?";args += [language] }
            if !clean.isEmpty {
                var choices=["d.id IN (SELECT rowid FROM search WHERE search MATCH ?)","d.id IN (SELECT documentID FROM target WHERE key=?)","d.id IN (SELECT t.documentID FROM target t JOIN nativeForm f ON f.lemmaKey=t.key JOIN document nd ON nd.id=t.documentID AND nd.language=f.language WHERE f.key=?)"]
                args += [match,clean,clean]
                for code in native.keys.sorted() {
                    let ids=native[code]!
                    if !ids.isEmpty {
                        choices.append("(d.language=? AND d.kind='lexeme' AND d.sourceID IN (\(Array(repeating:"?",count:ids.count).joined(separator:","))))")
                        args += [code];args += StatementArguments(ids)
                    }
                }
                sql += " AND ("+choices.joined(separator:" OR ")+")"
                sql += " ORDER BY CASE WHEN d.englishKey=? THEN 0 WHEN d.id IN (SELECT documentID FROM target WHERE key=?) THEN 1 ELSE 2 END,d.language,d.englishKey,d.id"
                args += [clean,clean]
            } else { sql += " ORDER BY d.language,d.englishKey,d.id" }
            sql += " LIMIT ? OFFSET ?";args += [size+1,offset]
            return try Row.fetchAll(db,sql:sql,arguments:args).map(Self.record)
        }
        try Task.checkCancellation()
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
            let sql="""
                SELECT 'noun:'||rowid AS ident,surface,coalesce(number,'')||' · '||coalesce(gender,'') AS analysis,source FROM nounForm WHERE lemma=?
                UNION ALL SELECT 'case:'||rowid,surface,coalesce(number,'')||' · '||coalesce(grammaticalCase,'')||' · '||coalesce(gender,''),source FROM caseForm WHERE lemma=?
                UNION ALL SELECT 'practice:'||rowid,surface,coalesce(form,'')||' · '||coalesce(tense,'')||' · '||coalesce(person,'')||' · '||coalesce(number,'')||' · '||coalesce(gender,''),source FROM practiceForm WHERE lemma=?
                ORDER BY ident LIMIT ? OFFSET ?
                """
            return try Row.fetchAll(db,sql:sql,arguments:[lemma,lemma,lemma,size+1,offset]).map { row in
                .init(id:row["ident"],surface:row["surface"],analysis:row["analysis"],transliteration:"",source:row["source"],lexicalReference:nil)
            }
        }
        return .init(forms:Array(forms.prefix(size)),hasMore:forms.count > size)
    }
    private static func record(_ r:Row) -> DictionaryRecord {
        .init(id:r["id"],language:r["language"],kind:DictionaryRecordKind(rawValue:r["kind"])!,sourceID:r["sourceID"],headword:r["headword"],english:r["english"],partOfSpeech:r["pos"],definition:r["definition"],transliteration:r["transliteration"])
    }
}
