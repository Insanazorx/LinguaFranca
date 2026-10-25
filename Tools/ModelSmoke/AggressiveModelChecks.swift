import Foundation
import LinguaFrancaCore
import LinguaFrancaInference

extension ModelSmoke {
    static func checkAggressiveModel(path:String,arguments:[String]) async throws {
        let directory=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/LanguagePacks")
        let registry=try LanguagePackRegistry(directory:directory)
        let model=LlamaCppService(modelURL:URL(fileURLWithPath:path),model:.aggressive)
        let service=AggressiveReadingGenerator(model:model,registry:registry)
        var rows:[[String:Any]]=[]
        for (index,domains) in [Set([PracticeDomain.structure]),Set([.actions]),Set([.structure,.actions]),Set([.prepositionalPhrases]),Set([.content])].enumerated() {
            if arguments.contains("--quick") && index > 0 { break }
            if let flag=arguments.firstIndex(of:"--profile"), arguments.indices.contains(flag+1),Int(arguments[flag+1]) != index { continue }
            var settings=AppSettings();settings.replacementMode = .aggressive;settings.practiceDomains=domains
            settings.aggressiveLanguageAssignments=["structure":"de","actions":"ru","content":"de","prepositionalPhrases":"de"]
            if let flag=arguments.firstIndex(of:"--languages"),arguments.indices.contains(flag+1) {
                settings.enabledLanguages=arguments[flag+1].split(separator:",").map(String.init)
                settings.aggressiveLanguageAssignments=[:]
            }
            do {
                let reading=try await service.generate(request:.init(topic:"A visit to a garden",seed:UInt32(91+index),aggressiveDomains:domains),settings:settings)
                let mixed=try reading.renderedText()
                rows.append(["domains":domains.map(\.rawValue).sorted(),"status":"passed-coverage","original":reading.originalEnglish,"mixed":mixed,"metadata":reading.metadata,"mappings":reading.replacements.map { ["en":$0.originalSurface,"target":$0.targetSurface,"language":$0.targetLanguageCode,"pos":$0.originalPartOfSpeech] }])
                print("AGGRESSIVE \(domains):\n\(mixed)")
            } catch {
                rows.append(["domains":domains.map(\.rawValue).sorted(),"status":"failed","error":error.localizedDescription]);print(error.localizedDescription)
            }
        }
        await model.unloadModel()
        if let flag=arguments.firstIndex(of:"--output"),arguments.indices.contains(flag+1) {
            try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:arguments[flag+1]))
        }
    }
}
