import Foundation
import GRDB

extension LatinVocabulary {
    public func practiceQuestions(query: String = "", pair: LatinVocabularyPair = .all, wordType: LatinVocabularyWordType = .all,
                                  families count: Int = 8, preferred: [String] = [], seed: UInt64) throws -> [CatalogQuestion] {
        guard query.count<=200 else { throw DomainError.invalidInput("Use a shorter search.") }
        let prefix=Self.filteredFamilies(query:OfflineDictionary.key(query.trimmingCharacters(in:.whitespacesAndNewlines)),pair:pair,wordType:wordType)
        let all=try database.read { try String.fetchAll($0,sql:prefix.sql+" SELECT id FROM filtered ORDER BY id",arguments:prefix.arguments) }
        let contextIDs=try database.read {db in
            var sql="SELECT DISTINCT familyID FROM member WHERE pos='noun' AND lower(trim(english)) IN (\(CatalogContexts.concepts.map{_ in "?"}.joined(separator:",")))"
            var args=StatementArguments(CatalogContexts.concepts)
            if wordType != .all && wordType != .nouns {sql += " AND 0"}
            if !pair.languages.isEmpty {sql += " AND language IN (\(pair.languages.map{_ in "?"}.joined(separator:",")))";args += StatementArguments(pair.languages)}
            return try String.fetchAll(db,sql:sql,arguments:args)
        }
        let contexts=Set(contextIDs)
        var rng=SeededGenerator(seed:seed), questions:[CatalogQuestion]=[]
        for id in CatalogSampling.families(all,preferred:preferred,contextFamilies:contextIDs,limit:count,rng:&rng) {
            try Task.checkCancellation()
            let members=try members(of:id,wordType:wordType)
            let title=try database.read { try String.fetchOne($0,sql:"SELECT originWord FROM family WHERE id=?",arguments:[id]) } ?? "Word family"
            let languages=pair.languages.isEmpty ? ["la","es","fr"] : pair.languages
            var selected:[LatinVocabularyMember]=[]
            for code in languages {
                var choices=members.filter{$0.record.language==code && !$0.record.english.isEmpty};choices.shuffle(using:&rng)
                let context=choices.first {CatalogContexts.make(english:$0.record.english,pos:$0.record.partOfSpeech) != nil}
                if let pick=(contexts.contains(id) || rng.next()%2==0 ? context : nil) ?? choices.first { selected.append(pick) }
            }
            let peers=selected.map {CatalogPracticePeer(language:$0.record.language,word:$0.record.headword,meaning:$0.record.english)}
            questions += selected.map { m in
                let r=m.record
                return .init(id:"latin:"+id+":"+m.id,familyID:id,familyTitle:title,language:r.language,word:r.headword,
                             meaning:r.definition.isEmpty ? r.english : r.definition,partOfSpeech:r.partOfSpeech,sourceID:r.sourceID,source:.latin,
                             context:CatalogContexts.make(english:r.english,pos:r.partOfSpeech),peers:peers)
            }
        }
        questions.shuffle(using:&rng);return questions
    }
}
extension SemiticFamilies {
    public func practiceQuestions(lexicon: SemiticLexicon, query: String = "", pair: SemiticFamilyPair = .all,
                                  families count: Int = 8, preferred: [String] = [], seed: UInt64) async throws -> [CatalogQuestion] {
        let (predicate,args)=try Self.predicate(query,pair:pair)
        let all=try await database.read { try String.fetchAll($0,sql:"SELECT f.id FROM family f WHERE \(predicate) ORDER BY f.id",arguments:args) }
        let contextRoots=Set(try await lexicon.contextRootIDs(languages:pair.languages))
        let contextIDs=try await database.read {db in
            try Row.fetchAll(db,sql:"SELECT familyID,rootID FROM member").filter{contextRoots.contains($0["rootID"] as String)}.map{$0["familyID"] as String}
        }
        let contexts=Set(contextIDs)
        var rng=SeededGenerator(seed:seed),questions:[CatalogQuestion]=[]
        for id in CatalogSampling.families(all,preferred:preferred,contextFamilies:contextIDs,limit:count,rng:&rng) {
            try Task.checkCancellation()
            let roots=try members(of:id)
            let title=try await database.read { try String.fetchOne($0,sql:"SELECT label FROM family WHERE id=?",arguments:[id]) } ?? "Root family"
            var selected:[SemiticLexeme]=[]
            for root in roots where pair.languages.isEmpty || pair.languages.contains(root.languageCode) {
                var choices=try await lexicon.lexemes(rootID:root.id,language:root.languageCode).filter {
                    !$0.lemma.contains(where:\.isWhitespace) && !$0.gloss.isEmpty && !$0.gloss.lowercased().contains("spelling of")
                }
                choices.shuffle(using:&rng)
                let context=choices.first {CatalogContexts.semitic(meaning:$0.gloss,pos:$0.partOfSpeech) != nil}
                if let pick=(contexts.contains(id) || rng.next()%2==0 ? context : nil) ?? choices.first { selected.append(pick) }
            }
            let peers=selected.map {CatalogPracticePeer(language:$0.languageCode,word:$0.lemma,meaning:$0.gloss)}
            questions += selected.map { l in
                .init(id:"semitic:"+id+":"+l.id,familyID:id,familyTitle:title,language:l.languageCode,word:l.lemma,meaning:l.gloss,
                      partOfSpeech:l.partOfSpeech,transliteration:l.transliteration,sourceID:l.id,pattern:l.pattern,source:.semitic,
                      context:CatalogContexts.semitic(meaning:l.gloss,pos:l.partOfSpeech),peers:peers)
            }
        }
        questions.shuffle(using:&rng);return questions
    }
}
