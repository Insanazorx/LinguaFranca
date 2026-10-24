import Foundation
import Darwin
import LinguaFrancaCore
import LinguaFrancaInference

extension ModelSmoke {
    static func checkSenses(path:String,arguments:[String]) async throws {
        let service = LlamaCppService(modelURL:URL(fileURLWithPath:path))
        let cases: [(String,String,[String],Int?)] = [
            ("moved in","Her hands trembled as the shadow [[moved in]] unison with the screams.",["to start living in a house or flat"],nil),
            ("moved in","She [[moved in]] yesterday and now lives in the house.",["to start living in a house or flat"],0),
            ("since","[[Since]] he is hungry, he eats the bread.",["because","from the time that"],0),
            ("since","She has lived here [[since]] she was a child.",["because","from the time that"],1),
            ("as","[[As]] she walks through the garden, she waves to her friend.",["at the same time that","considering that, because","in the same way that"],0),
            ("as","She does [[as]] her teacher instructs.",["at the same time that","considering that, because","in the same way that"],2)
        ]
        var records: [[String:Any]] = []
        for (expression,sentence,definitions,expected) in cases {
            let request = ContextualSenseRequest(expression:expression,partOfSpeech:"expression",sentence:sentence,languageCode:"en",options:definitions.map{.init(definition:$0,target:"dictionary")})
            let selection = try await service.selectSense(request)
            records.append(["sentence":sentence,"definitions":definitions,"expected":expected.map{ $0+1 } ?? 0,"selected":selection.map{$0+1} ?? 0,"passed":selection==expected])
            print("SENSE \(selection==expected ? "PASS" : "FAIL") \(sentence) -> \(selection.map{$0+1} ?? 0)")
        }
        await service.unloadModel()
        if let flag = arguments.firstIndex(of:"--output"),arguments.indices.contains(flag+1) {
            try JSONSerialization.data(withJSONObject:records,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:arguments[flag+1]),options:.atomic)
        }
        if !records.allSatisfy({$0["passed"] as? Bool == true}) { exit(1) }
    }
    static func checkAggressive(path:String,arguments:[String]) async throws {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let registry = try LanguagePackRegistry(directory:root.appendingPathComponent("Resources/LanguagePacks"))
        let service = LlamaCppService(modelURL:URL(fileURLWithPath:path))
        let engine = ContextualReplacementEngine(registry:registry,senseSelector:service)
        let planner = GenerationVocabularyPlanner(registry:registry)
        let quick = arguments.contains("--quick")
        let profiles: [(String,Set<PracticeDomain>)] = quick ? [("structure",[.structure]),("actions",[.actions])] : [
            ("structure",[.structure]),("actions",[.actions]),("content",[.content]),("combined",[.structure,.content,.actions]),("phrases",[.prepositionalPhrases])]
        let languages = quick ? [["de"],["ru"]] : [["de"],["ru"],["de","ru"]]
        var records: [[String:Any]] = [], session = ReadingSession(), sequence = 0
        for (name,domains) in profiles {
            for codes in languages {
                var settings = AppSettings(); settings.replacementMode = .aggressive; settings.practiceDomains = domains
                settings.enabledLanguages = codes; settings.languageFrequencies = Dictionary(uniqueKeysWithValues:codes.map{($0,0)})
                var avoid: Set<String> = [], attempts: [[String:Any]] = [], completed = false
                for attempt in 0..<3 {
                    let seed = UInt32(810+sequence*10+attempt)
                    do {
                        let genre: WritingGenre = quick ? .story : [.story,.essay,.dialogue][sequence%3]
                        let request = GenerationRequest(topic:"Daily life",seed:seed,targetLanguageCodes:codes,
                            vocabularyHints:try await planner.hints(topic:"Daily life",settings:settings,seed:seed),
                            scenario:try session.nextScenario(seed:seed),previousPassages:session.fingerprints,genre:genre,
                            aggressiveDomains:domains,avoidWords:avoid.sorted())
                        let output = try await service.generate(request:request)
                        let id = UUID().uuidString
                        let mix = try await engine.replace(text:output.englishText,sourceTextID:id,settings:settings,seed:seed)
                        let text = GeneratedText(id:id,originalEnglish:output.englishText,topic:"Test",cefrLevel:.c1,
                            modelID:output.modelIdentifier,seed:seed,metadata:output.metadata,replacements:mix.spans)
                        try session.append(text)
                        attempts.append(["attempt":attempt+1,"source":output.englishText,"rendered":try text.renderedText(),
                            "wordCount":mix.wordCount,"selectedDensity":Double(mix.eligibleWordCount)/Double(max(1,mix.wordCount)),"eligible":mix.eligibleWordCount,"translated":mix.replacedWordCount,"complete":mix.isComplete,
                            "gaps":mix.unresolved.map{$0.contextExpression ?? $0.surface},"spans":mix.spans.map{["source":$0.originalSurface,"target":$0.targetSurface,"language":$0.targetLanguageCode,"meaning":$0.senseDescription ?? ""]}])
                        print("REGRESSION \(name) \(codes.joined(separator:"+")) attempt \(attempt+1): \(mix.replacedWordCount)/\(mix.eligibleWordCount) gaps=\(mix.unresolved.map(\.surface))")
                        if mix.isComplete { completed = true; break }
                        avoid.formUnion(mix.unresolved.map{$0.contextExpression ?? $0.surface})
                    } catch {
                        attempts.append(["attempt":attempt+1,"error":error.localizedDescription])
                        print("REGRESSION \(name) \(codes): \(error.localizedDescription)")
                    }
                }
                records.append(["profile":name,"languages":codes,"complete":completed,"attempts":attempts]); sequence += 1
                if let flag = arguments.firstIndex(of:"--output"), arguments.indices.contains(flag+1) {
                    try JSONSerialization.data(withJSONObject:records,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:arguments[flag+1]),options:.atomic)
                }
            }
        }
        await service.unloadModel()
        if !records.allSatisfy({$0["complete"] as? Bool == true}) { exit(1) }
    }
}
