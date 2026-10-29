import Foundation
import SwiftUI
import Observation

import LinguaFrancaCore
import LinguaFrancaInference

@MainActor @Observable final class AppEnvironment {
    private(set) var database: DatabaseManager?
    private(set) var decks: [StudyDeck] = []
    private(set) var vocabulary: [VocabularyItem] = []
    private(set) var readingSession = ReadingSession()
    var passages: [GeneratedText] { readingSession.visiblePassages }
    var passageCount: Int { passages.count }
    private(set) var settings = AppSettings()
    private(set) var summary: StudySummary?
    private(set) var generating = false
    private(set) var loading = true
    private(set) var storageBytes: Int64 = 0
    private(set) var languagePacks: [LanguagePackMetadata] = []
    private(set) var remixing = false
    private(set) var vocabularyReadings: [VocabularyPracticeReading] = []
    private(set) var activeVocabularyGroup: String?
    private(set) var vocabularyBatchProgress = 0
    private(set) var vocabularyBatchTotal = 0
    var selectedSection: MacSection? = .generate
    var reviewSession: ReviewPresentation?
    var studyDeckID = ""
    var errorMessage: String?
    private(set) var generationMessage: String?
    private(set) var generationPhase = ""
    let narrationLanguages=["ru"]
    let narrationVoiceNames=["ru":"Denis"]
    private(set) var savedReadings:[SavedReadingSummary]=[]
    private(set) var narrationReadings:[String:[String:TargetReading]]=[:]
    private(set) var preparingNarrationID:String?
    private(set) var narrationErrorMessage:String?
    private(set) var narrationErrorSourceID:String?
    let narrator=PassageNarrator(speech:PiperSpeechService(directory:(Bundle.main.resourceURL ?? URL(fileURLWithPath:".")).appendingPathComponent("Speech")),aligner:RussianSpeechAligner(directory:(Bundle.main.resourceURL ?? URL(fileURLWithPath:".")).appendingPathComponent("Speech")))
    private var generationTask: Task<Void, Never>?
    private var refreshID = 0
    private var settingsRevision = 0
    @ObservationIgnored private var settingsWriteTask: Task<Void, Never>?
    let modelURL: URL?
    let aggressiveModelURL: URL?
    var modelDisplayName: String { settings.replacementMode == .aggressive ? BundledModel.aggressive.identifier : BundledModel.qwen35.identifier }
    let availableTopics = ["Random", "Daily life", "Work and careers", "Technology", "Science", "Psychology", "Society", "Travel", "Literature", "Education", "Culture"]
    private let generator: ModeGenerationService
    private var aggressiveGenerator: AggressiveReadingGenerator?
    private var replacementEngine: ContextualReplacementEngine?
    private var vocabularyPlanner: GenerationVocabularyPlanner?
    private var practicePlanner: VocabularyPracticePlanner?
    private(set) var semiticLexicon: SemiticLexicon?
    private(set) var dictionary: OfflineDictionary?
    private var addonDirectory:URL?
    private(set) var installingLanguagePack=false
    private(set) var latinVocabulary:LatinVocabulary?
    private var vocabularyTextGenerator: VocabularyTextGenerator?
    var canGenerate: Bool { (settings.replacementMode == .aggressive ? aggressiveModelURL : modelURL) != nil && replacementEngine != nil && !loading && !installingLanguagePack }
    func canGenerateVocabulary(_ language: String) -> Bool { language == "syc" ? semiticLexicon != nil && !loading : canGenerate }

    init() {
        let name = (BundledModel.qwen35.filename as NSString).deletingPathExtension
        let url = Bundle.main.url(forResource: name, withExtension: "gguf", subdirectory: "Models")
        modelURL = url
        aggressiveModelURL=Bundle.main.url(forResource:(BundledModel.aggressive.filename as NSString).deletingPathExtension,withExtension:"gguf",subdirectory:"Models")
        generator = ModeGenerationService(balancedURL:url,aggressiveURL:aggressiveModelURL)
    }

    func open() async {
        guard database == nil else { return }
        loading = true
        do {
            // Keep existing user lists/settings when upgrading the former preview bundle to real inference.
            var folderName = Bundle.main.bundleIdentifier?.hasSuffix(".preview") == true ? "LinguaFrancaPreview" : "LinguaFranca"
            #if DEBUG
            if let flag=ProcessInfo.processInfo.arguments.first(where: { $0 == "--srs-ui-test" || $0.hasPrefix("--srs-ui-test=") }) {
                let name=flag.split(separator:"=",maxSplits:1).dropFirst().first.map(String.init) ?? "default"
                folderName="LinguaFrancaSRSUITests-" + String(name.filter { $0.isASCII && $0.isLetter || $0.isNumber }.prefix(40))
            }
            #endif
            let storageFolderName=folderName
            database = try await Task.detached(priority: .userInitiated) {
                let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: true)
                let folder = base.appendingPathComponent(storageFolderName, isDirectory: true)
                let attributes:[FileAttributeKey:Any]=[.posixPermissions:0o700]
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:attributes)
                let database = try DatabaseManager(path: folder.appendingPathComponent("library.sqlite").path)
                return database
            }.value
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains(where: { $0 == "--srs-ui-test" || $0.hasPrefix("--srs-ui-test=") }), let database, try await database.decks().isEmpty {
                let deck=try await database.createDeck(name:"SRS interface test")
                for (en,de) in [("garden","Garten"),("moon","Mond")] {
                    _ = try await database.saveVocabulary(.init(englishLemma:en,targetLanguage:"de",targetLemma:de,targetSurface:de,senseID:"ui-fixture",partOfSpeech:"noun",exampleEnglish:"The \(en) is beautiful."),inDeck:deck)
                }
            }
            #endif
            try await refresh()
            let support=try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true)
            addonDirectory=support.appendingPathComponent(storageFolderName,isDirectory:true).appendingPathComponent("LanguageAddons",isDirectory:true)
            try await reloadLanguagePacks()

        } catch { errorMessage = error.localizedDescription }
        loading = false
    }

    private func reloadLanguagePacks() async throws {
        guard let directory=Bundle.main.url(forResource:"LanguagePacks",withExtension:nil),let addonDirectory else { throw DomainError.invalidInput("The bundled language packs are missing.") }
        let loaded=try await Task.detached(priority:.userInitiated) {
            let extras=try LanguagePackAddon.installedDirectories(in:addonDirectory)
            let registry=try LanguagePackRegistry(directory:directory,additionalDirectories:extras)
            let dictionary=try OfflineDictionary(directory:directory,additionalDirectories:extras)
            return (registry,dictionary)
        }.value
        let registry=loaded.0
        languagePacks=registry.packs.map(\.metadata);dictionary=loaded.1
        replacementEngine=ContextualReplacementEngine(registry:registry,senseSelector:generator)
        aggressiveGenerator=AggressiveReadingGenerator(model:generator,registry:registry)
        vocabularyPlanner=GenerationVocabularyPlanner(registry:registry)
        let semitic=try await Task.detached(priority:.userInitiated) {try SemiticLexicon(directory:directory)}.value
        semiticLexicon=semitic
        practicePlanner=VocabularyPracticePlanner(registry:registry,semiticLexicon:semitic)
        vocabularyTextGenerator=VocabularyTextGenerator(model:generator,lexicon:semitic)
        let latinURL=directory.appendingPathComponent("_latin/etymology.sqlite")
        if FileManager.default.fileExists(atPath:latinURL.path) {
            latinVocabulary=try await Task.detached(priority:.userInitiated) {try LatinVocabulary(databaseURL:latinURL)}.value
        }
    }
    func installLanguagePack(from url:URL) async throws {
        guard !generating,!remixing,!installingLanguagePack,let addonDirectory else { throw DomainError.invalidInput("Finish the current activity before adding a language.") }
        installingLanguagePack=true;defer {installingLanguagePack=false}
        let scoped=url.startAccessingSecurityScopedResource();defer {if scoped {url.stopAccessingSecurityScopedResource()}}
        let installer=LanguagePackInstaller(directory:addonDirectory)
        _ = try await installer.install(from:url,existingCodes:Set(languagePacks.map(\.languageCode)))
        try await reloadLanguagePacks()
    }

    func refresh() async throws {
        guard let database else { return }
        refreshID += 1
        let id = refreshID, requestedSettingsRevision = settingsRevision
        await settingsWriteTask?.value
        async let fetchedDecks = database.decks()
        async let fetchedWords = database.vocabulary()
        async let fetchedSettings = database.settings()
        async let fetchedSummary = database.studySummary()
        async let fetchedBytes = database.storageBytes()
        async let fetchedReadings = database.savedReadings()
        let result = try await (fetchedDecks, fetchedWords, fetchedSettings, fetchedSummary, fetchedBytes, fetchedReadings)
        guard id == refreshID else { return }
        (decks, vocabulary, summary, storageBytes, savedReadings) = (result.0, result.1, result.3, result.4, result.5)
        if requestedSettingsRevision == settingsRevision, settingsWriteTask == nil { settings = result.2 }
    }

    func perform(_ operation: (DatabaseManager) async throws -> Void) async {
        guard let database else { errorMessage = "Your library is unavailable. Reopen the app to try again."; return }
        do { try await operation(database); try await refresh() }
        catch { errorMessage = error.localizedDescription }
    }

    /// Apply the UI change synchronously, then serialize local writes. Fast taps
    /// cannot copy stale settings or allow an older write to win after a newer one.
    func autosaveSettings(_ value: AppSettings) {
        guard let database else { errorMessage = "Your library is unavailable."; return }
        do { try value.validate() } catch { errorMessage = error.localizedDescription; return }
        guard value != settings else { return }
        settingsRevision += 1
        let revision = settingsRevision, previousWrite = settingsWriteTask
        settings = value
        settingsWriteTask = Task {
            await previousWrite?.value
            do { try await database.saveSettings(value) }
            catch {
                errorMessage = "Preferences could not be saved: " + error.localizedDescription
                if revision == settingsRevision, let persisted = try? await database.settings(), revision == settingsRevision {
                    settings = persisted
                }
            }
            if revision == settingsRevision { settingsWriteTask = nil }
        }
    }
    func updateSettings(_ value: AppSettings) async throws {
        try value.validate()
        guard database != nil else { throw DomainError.missingRecord }
        autosaveSettings(value)
        await settingsWriteTask?.value
    }

    func generate(topic: String) {
        guard !generating else { return }
        guard canGenerate, database != nil else { errorMessage = "The local model and language packs are not ready. Reopen the app and try again."; return }
        generating = true; generationMessage = nil; generationPhase = "Writing on your device…"
        if settings.replacementMode == .aggressive {
            let current=settings
            generationTask=Task {
                defer { generating=false; generationTask=nil }
                do {
                    await narrator.unload()
                    guard let aggressiveGenerator else { throw DomainError.missingRecord }
                    generationPhase="Qwen3.5-2B is writing your mixed reading…"
                    let seed=UInt32.random(in:0..<UInt32.max)
                    let request=GenerationRequest(topic:topic,level:current.generationLevel,seed:seed,scenario:try readingSession.nextScenario(seed:seed),previousPassages:readingSession.fingerprints,genre:current.writingGenre,aggressiveDomains:current.practiceDomains)
                    let ready=try await aggressiveGenerator.generate(request:request,settings:current) { [weak self] source in
                        await self?.publishAggressiveSource(source)
                    }
                    try Task.checkCancellation()
                    try readingSession.remix(ready)
                    let omitted=ready.metadata["unrepresentedLanguages"] ?? ""
                    generationMessage=omitted.isEmpty ? nil : "No suitable expression was available for: " + omitted + ". Other selected languages are shown."
                } catch {
                    generationMessage = error is CancellationError ? "Generation stopped. Any completed English draft remains below." : error.localizedDescription
                    for source in passages where source.metadata["replacementStatus"] == "processing" {
                        var meta=source.metadata;meta["replacementStatus"]="failed";meta["replacementComplete"]="false"
                        try? readingSession.remix(.init(id:source.id,originalEnglish:source.originalEnglish,topic:source.topic,cefrLevel:source.cefrLevel,generatedAt:source.generatedAt,modelID:source.modelID,seed:source.seed,metadata:meta))
                    }
                }
            }
            return
        }
        let generator = generator, current = settings, engine = replacementEngine, planner = vocabularyPlanner
        generationTask = Task {
            defer { generating = false; generationTask = nil }
            let groupID = UUID().uuidString
            var avoid: Set<String> = []
            let limit = current.replacementMode == .aggressive ? 3 : 1
            do {
                await narrator.unload()
                for attempt in 0..<limit {
                    try Task.checkCancellation()
                    generationPhase = attempt == 0 ? "Writing on your device…" : "Preparing a fully translated reading (\(attempt+1)/\(limit))…"
                    let seed = UInt32.random(in: 0..<UInt32.max)
                    let scenario = try readingSession.nextScenario(seed: seed)
                    let hints = try await planner?.hints(topic: topic, settings: current, seed: seed) ?? []
                    let request = GenerationRequest(topic: topic, level: current.generationLevel,
                        wordCount: current.defaultWordCount, seed: seed,
                        targetLanguageCodes: current.replacementLanguageShares.filter { $0.value > 0 }.keys.sorted(),
                        vocabularyHints: hints, scenario: scenario, previousPassages: readingSession.fingerprints, genre: current.writingGenre,
                        aggressiveDomains: current.replacementMode == .aggressive ? current.practiceDomains : [], avoidWords: avoid.sorted())
                    let result = try await generator.generate(request: request)
                    try Task.checkCancellation()
                    var metadata = result.metadata
                    metadata["durationSeconds"] = String(result.duration); metadata["tokenCount"] = String(result.tokenCount)
                    metadata["generationGroupID"] = groupID; metadata["replacementStatus"] = "processing"
                    Self.addFocusMetadata(current,to:&metadata)
                    let id = UUID().uuidString
                    let source = GeneratedText(id:id,originalEnglish:result.englishText,topic:topic,cefrLevel:request.level,
                        modelID:result.modelIdentifier,seed:result.seed,metadata:metadata)
                    try readingSession.append(source)
                    generationPhase = "Preparing translations…"
                    do {
                        guard let engine else { throw DomainError.invalidInput("The local language packs are unavailable.") }
                        let mix = try await engine.replace(text:source.originalEnglish,sourceTextID:id,settings:current,seed:result.seed)
                        try Task.checkCancellation()
                        Self.addReplacementMetadata(mix,to:&metadata)
                        let complete = current.replacementMode != .aggressive || mix.isComplete
                        metadata["replacementComplete"] = String(complete)
                        // An incomplete Aggressive draft is never presented as a finished mixed text.
                        let ready = GeneratedText(id:id,originalEnglish:source.originalEnglish,topic:topic,cefrLevel:request.level,
                            generatedAt:source.generatedAt,modelID:result.modelIdentifier,seed:result.seed,metadata:metadata,replacements:complete ? mix.spans : [])
                        try readingSession.remix(ready)
                        if complete { generationMessage = nil; return }
                        avoid.formUnion(mix.unresolved.map { $0.contextExpression ?? $0.surface })
                        generationMessage = "Aggressive translation is incomplete. Finding a reading where every selected component can be translated correctly…"
                    } catch is CancellationError {
                        metadata["replacementStatus"] = "cancelled"; metadata["replacementComplete"] = "false"
                        try? readingSession.remix(GeneratedText(id:id,originalEnglish:source.originalEnglish,topic:topic,cefrLevel:source.cefrLevel,
                            generatedAt:source.generatedAt,modelID:source.modelID,seed:source.seed,metadata:metadata))
                        generationMessage = "Translation stopped. Your generated text is still available below."; return
                    } catch {
                        metadata["replacementStatus"] = "failed"; metadata["replacementComplete"] = "false"
                        try? readingSession.remix(GeneratedText(id:id,originalEnglish:source.originalEnglish,topic:topic,cefrLevel:source.cefrLevel,
                            generatedAt:source.generatedAt,modelID:source.modelID,seed:source.seed,metadata:metadata))
                        generationMessage = "Your text is ready. Translation could not finish: " + error.localizedDescription; return
                    }
                }
                generationMessage = "A fully verified Aggressive translation could not be completed. The English text is kept below; no uncertain translation was forced. Try another generation or selection."
            } catch is CancellationError { generationMessage = "Generation stopped. Any completed text is still available below." }
            catch { generationMessage = error.localizedDescription; if passages.isEmpty { errorMessage = error.localizedDescription } }
        }
    }

    func narrate(_ passage:GeneratedText, languageCode:String="ru") {
        guard !generating,!remixing else{return}
        generating=true;preparingNarrationID=passage.id;narrationErrorMessage=nil;narrationErrorSourceID=passage.id
        SentenceSpeechController.active?.stop()
        generationPhase="Preparing Russian reading…"
        generationTask=Task {
            defer {generating=false;preparingNarrationID=nil;generationTask=nil}
            do {
                await narrator.unload()
                let reading:TargetReading
                if let cached=narrationReadings[passage.id]?[languageCode] {reading=cached}
                else {
                    reading=try await TargetReadingTranslator(model:generator).translate(passage,languageCode:languageCode) { [weak self] done,total in
                        await self?.narrationProgress(done,total)
                    }
                    try reading.validate(for:passage)
                }
                try Task.checkCancellation()
                await generator.unloadModel()
                try Task.checkCancellation()
                narrationReadings[passage.id,default:[:]][languageCode]=reading
                if savedReadings.contains(where:{$0.id==passage.id}),let database {
                    try await database.saveReadingTranslation(reading)
                }
                narrator.play(reading)
            } catch is CancellationError {await generator.unloadModel()}
            catch {await generator.unloadModel();narrationErrorMessage=error.localizedDescription}
        }
    }
    private func narrationProgress(_ done:Int,_ total:Int) {
        generationPhase="Preparing Russian reading · \(done) / \(total)…"
    }
    func saveReading(_ passage:GeneratedText) async throws {
        guard let database else {throw DomainError.missingRecord}
        try await database.saveReading(passage,title:passage.metadata["title"] ?? passage.topic,translations:narrationReadings[passage.id] ?? [:])
        try await refresh()
    }
    func openSavedReading(_ id:String) async throws -> SavedReading {
        guard let database else {throw DomainError.missingRecord}
        let saved=try await database.savedReading(id:id)
        for (language,reading) in saved.translations {try reading.validate(for:saved.passage);narrationReadings[id,default:[:]][language]=reading}
        return saved
    }
    func deleteSavedReading(_ id:String) async {
        if narrator.reading?.sourceTextID==id {narrator.stop()}
        await perform {try await $0.deleteReading(id:id)}
        narrationReadings[id]=nil
    }

    func cancelGeneration() { generationTask?.cancel(); narrator.stop() }
    private func publishAggressiveSource(_ source:GeneratedText) {
        do { try readingSession.append(source); generationPhase="Checking every selected component…" }
        catch { generationMessage=error.localizedDescription }
    }
    func generateVocabulary(items: [VocabularyItem], languageCode: String, groupID: String) {
        guard !generating, canGenerateVocabulary(languageCode) else { return }
        generating = true; activeVocabularyGroup = groupID
        vocabularyBatchProgress = 0; vocabularyBatchTotal = 0
        generationTask = Task {
            defer { generating = false; activeVocabularyGroup = nil; generationTask = nil }
            do {
                await narrator.unload()
                let batches: [VocabularyPracticeRequest]
                if let practicePlanner { batches = try await practicePlanner.batches(items: items, languageCode: languageCode) }
                else { batches = try VocabularyPracticeRequest.batches(items: items, languageCode: languageCode) }
                vocabularyBatchTotal = batches.count
                vocabularyReadings.removeAll { $0.groupID == groupID }
                for batch in batches {
                    try Task.checkCancellation()
                    let seed = UInt32.random(in: 0..<UInt32.max)
                    let scene = try readingSession.nextScenario(seed: seed)
                    let request = GenerationRequest(topic: "Vocabulary practice", level: settings.generationLevel,
                        wordCount: 90, seed: seed, scenario: scene,
                        previousPassages: vocabularyReadings.filter { $0.languageCode == languageCode }.map { PassageFingerprint($0.text) }, vocabularyPractice: batch)
                    guard let vocabularyTextGenerator else { throw DomainError.invalidInput("Vocabulary writing is unavailable.") }
                    let annotated = try await vocabularyTextGenerator.generate(request:request)
                    let result = annotated.generation
                    try Task.checkCancellation()
                    vocabularyReadings.append(.init(groupID: groupID, languageCode: languageCode,
                        text: result.englishText, expressionIDs: batch.expressions.map(\.id),coverage:annotated.coverage))
                    vocabularyBatchProgress += 1
                }
            } catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }
    func remix(_ passage: GeneratedText) async {
        guard !remixing, !generating, let engine = replacementEngine else { return }
        remixing = true
        defer { remixing = false }
        do {
            if settings.replacementMode == .aggressive {
                guard let aggressiveGenerator else { throw DomainError.missingRecord }
                let ready=try await aggressiveGenerator.remix(passage,settings:settings)
                try Task.checkCancellation();try readingSession.remix(ready);generationMessage=nil
                return
            }
            let mix = try await engine.replace(text: passage.originalEnglish, sourceTextID: passage.id, settings: settings, seed: passage.seed)
            var metadata = passage.metadata
            Self.addReplacementMetadata(mix, to: &metadata)
            Self.addFocusMetadata(settings, to: &metadata)
            let updated = GeneratedText(id: passage.id, originalEnglish: passage.originalEnglish, topic: passage.topic,
                cefrLevel: passage.cefrLevel, generatedAt: passage.generatedAt, modelID: passage.modelID,
                seed: passage.seed, metadata: metadata, replacements: settings.replacementMode == .aggressive && !mix.isComplete ? [] : mix.spans)
            try Task.checkCancellation()
            try readingSession.remix(updated)
            if settings.replacementMode == .aggressive, !mix.isComplete {
                generationMessage = "Aggressive translation is incomplete: " + mix.unresolved.map(\.surface).joined(separator:", ") + ". Generate a new reading for this selection."
            } else { generationMessage = nil }
        } catch { errorMessage = error.localizedDescription }
    }
    private static func addReplacementMetadata(_ result: ReplacementResult?, to metadata: inout [String:String]) {
        metadata["eligibleWordCount"] = String(result?.eligibleWordCount ?? 0)
        metadata["replacementStatus"] = result == nil ? "language-packs-unavailable" : "local-lexicon"
        metadata["requestedDensity"] = String(result?.requestedDensity ?? 0)
        metadata["actualDensity"] = String(result?.actualDensity ?? 0)
        metadata["replacementWordCount"] = String(result?.wordCount ?? 0)
        metadata["replacementCount"] = String(result?.spans.count ?? 0)
        metadata["replacedWordCount"] = String(result?.replacedWordCount ?? 0)
        metadata["replacementEngineVersion"] = "contextual-7-complete"
        metadata["replacementComplete"] = String(result?.isComplete ?? false)
        metadata["unresolvedWordCount"] = String(result?.unresolved.count ?? 0)
        metadata["unresolvedWords"] = result?.unresolved.map(\.surface).joined(separator:" · ") ?? ""
        for key in metadata.keys.filter({ $0.hasPrefix("replacementCount.") }) { metadata.removeValue(forKey:key) }
        for (code, count) in result?.languageCounts ?? [:] { metadata["replacementCount.\(code)"] = String(count) }
    }
    private static func addFocusMetadata(_ settings: AppSettings, to metadata: inout [String:String]) {
        metadata["replacementMode"] = settings.replacementMode.rawValue
        metadata["practiceDomains"] = settings.practiceDomains.map(\.rawValue).sorted().joined(separator: ",")
    }
    func releaseModel() async {
        await settingsWriteTask?.value
        generationTask?.cancel()
        await generator.unloadModel()
        await narrator.unload()
    }
}
