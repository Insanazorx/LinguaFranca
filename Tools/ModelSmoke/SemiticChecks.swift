import Foundation
import Darwin
import LinguaFrancaCore
import LinguaFrancaInference

extension ModelSmoke {
    static func checkSemitic(path:String,arguments:[String]) async throws {
        let directory=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/LanguagePacks")
        let registry=try LanguagePackRegistry(directory:directory),catalog=try SemiticLexicon(directory:directory)
        let model=LlamaCppService(modelURL:URL(fileURLWithPath:path))
        let planner=VocabularyPracticePlanner(registry:registry,semiticLexicon:catalog)
        let service=VocabularyTextGenerator(model:model,lexicon:catalog)
        var records: [[String:Any]] = []
        for (index,pair) in [("ar","كتب"),("he","כתב"),("syc","ܟܬܒ")].enumerated() {
            let (code,letters)=pair
            if let flag=arguments.firstIndex(of:"--only-language"),arguments.indices.contains(flag+1),arguments[flag+1] != code { continue }
            guard let root=try await catalog.roots(language:code,search:letters).first(where:{$0.native.replacingOccurrences(of:" ",with:"")==letters}) else { throw DomainError.missingRecord }
            let item=VocabularyItem(id:"selected-"+code,draft:root.vocabularyDraft,createdAt:.now)
            let request=try await planner.batches(items:[item],languageCode:code)[0]
            do {
                let result=try await service.generate(request:.init(topic:"Study",seed:UInt32(234+index),vocabularyPractice:request))
                let row: [String:Any] = ["language":code,"required":request.expressions.map(\.target),"prompt":request.prompt,"text":result.generation.englishText,"backend":result.generation.modelIdentifier,"seconds":result.generation.duration,
                    "used":result.coverage.usedIDs,"omitted":result.coverage.omittedIDs,"sourceReferences":result.coverage.sourceReferences,"validation":result.coverage.validationNote,
                    "annotations":result.coverage.annotations.map { ["surface":$0.surface,"start":$0.range.location,"length":$0.range.length,"formIDs":$0.forms.map(\.id)] },"passed":result.coverage.usedIDs.contains(item.id)]
                records.append(row)
                print("SEMITIC \(code): used=\(result.coverage.usedIDs.count); \(result.generation.englishText)")
            } catch {
                records.append(["language":code,"passed":false,"error":error.localizedDescription]);print("SEMITIC \(code): \(error.localizedDescription)")
            }
            if let flag=arguments.firstIndex(of:"--output"),arguments.indices.contains(flag+1) {
                try JSONSerialization.data(withJSONObject:records,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:arguments[flag+1]),options:.atomic)
            }
        }
        await model.unloadModel()
        if !records.allSatisfy({$0["passed"] as? Bool==true}) { exit(1) }
    }
}
