import Foundation
import CryptoKit
import llama
import LinguaFrancaCore

public struct BundledModel: Codable, Sendable {
    public let identifier: String
    public let filename: String
    public let sha256: String
    public let byteCount: Int64
    public let revision: String
    public let license: String
    public static let qwen35 = BundledModel(
        identifier: "Qwen3.5-0.8B-Q4_K_M", filename: "Qwen3.5-0.8B-Q4_K_M.gguf",
        sha256: "bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517",
        byteCount: 532_517_120, revision: "6ab461498e2023f6e3c1baea90a8f0fe38ab64d0", license: "Apache-2.0"
    )
    public static let aggressive = BundledModel(identifier:"Qwen3.5-2B-Q4_K_M",filename:"Qwen3.5-2B-Q4_K_M.gguf",
        sha256:"57a1085840f497d764a7fc5d346922dbde961efb54cc792ea81d694fd846a1d8",byteCount:1_396_198_496,
        revision:"7d26695454df6de5fbcce2e58681e62dae06ce43",license:"Apache-2.0")
}

/// Coordinates task cancellation while the worker owns all native handles on its own executor.
public actor LlamaCppService: TextGenerationService, ContextualSenseSelecting {
    private let worker: LlamaWorker
    private var active: Task<GenerationResult, Error>?
    private var activeID: UUID?
    private var unloading = false
    public init(modelURL: URL?, model: BundledModel = .qwen35) { worker = LlamaWorker(url: modelURL, descriptor: model) }
    public func loadModel() async throws {
        guard !unloading else { throw GenerationError.busy }
        try await worker.load()
    }
    public func generate(request: GenerationRequest) async throws -> GenerationResult {
        try request.validate()
        if request.vocabularyPractice?.languageCode == "syc" { throw GenerationError.invalidOutput("Classical Syriac requires the corpus backend") }
        try Task.checkCancellation()
        guard active == nil, !unloading else { throw GenerationError.busy }
        let worker = worker, id = UUID()
        let task = Task.detached(priority: .userInitiated) { try await worker.generate(request) }
        active = task; activeID = id
        defer { if activeID == id { active = nil; activeID = nil } }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
    public func cancelGeneration() { active?.cancel() }
    public func selectSense(_ request: ContextualSenseRequest) async throws -> Int? {
        var configuration = GenerationConfiguration(); configuration.maximumTokens = 64; configuration.temperature = 0
        let result = try await generate(request:.init(topic:"Dictionary sense",seed:42,configuration:configuration,senseSelection:request))
        guard let index = try request.selection(result.englishText) else { return nil }
        // A small model can prefer the first numbered option even when no sense fits.
        // Contrast its selection with an explicit rejection option before accepting it.
        let verification = ContextualSenseRequest(expression:request.expression,partOfSpeech:request.partOfSpeech,sentence:request.sentence,languageCode:request.languageCode,
            options:[.init(definition:"This definition does not fit: the marked expression has a different meaning or is a literal combination of separate words.",target:"no match"),request.options[index]])
        let checked = try await generate(request:.init(topic:"Dictionary sense verification",seed:43,configuration:configuration,senseSelection:verification))
        return try verification.selection(checked.englishText) == 1 ? index : nil
    }
    public func unloadModel() async {
        guard !unloading else { return }
        unloading = true
        defer { unloading = false }
        if let task = active { task.cancel(); _ = await task.result }
        await worker.unload()
    }
    public func preferCPUForMemoryPressure() async {
        await unloadModel()
        await worker.preferCPUForMemoryPressure()
    }
}

/// The pointer never escapes LlamaWorker; the immutable wrapper only supplies deterministic destruction.
private final class NativeModel: @unchecked Sendable {
    let pointer: OpaquePointer
    init(_ pointer: OpaquePointer) { self.pointer = pointer }
    deinit { autoreleasepool {llama_model_free(pointer)} }
}

private enum Backend {
    // Process-wide initialization. Do not tear down a backend another service may still use.
    static let initialized: Void = llama_backend_init()
}

private actor LlamaWorker {
    private let url: URL?
    private let descriptor: BundledModel
    private var model: NativeModel?
    private var preferCPU=false
    private var memoryPolicy:InferenceMemoryPolicy {.current(modelBytes:descriptor.byteCount,preferCPU:preferCPU)}
    init(url: URL?, descriptor: BundledModel) { self.url = url; self.descriptor = descriptor }
    func load() throws {
        if model != nil { return }
        try Task.checkCancellation()
        guard let url, FileManager.default.fileExists(atPath: url.path) else { throw GenerationError.missingModel }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.size] as? NSNumber)?.int64Value == descriptor.byteCount else { throw GenerationError.checksumMismatch }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hasher = SHA256()
        // Drain Foundation temporaries per chunk on this long-running worker thread.
        // Hashing a 1.4 GB model must never retain a model-sized set of NSData buffers.
        while try autoreleasepool(invoking: {
            try Task.checkCancellation()
            guard let data=try file.read(upToCount:4*1024*1024),!data.isEmpty else {return false}
            hasher.update(data:data)
            return true
        }) {}
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == descriptor.sha256 else { throw GenerationError.checksumMismatch }
        _ = Backend.initialized
        var parameters = llama_model_default_params()
        parameters.load_mode = LLAMA_LOAD_MODE_MMAP
        parameters.n_gpu_layers = memoryPolicy.gpuLayers
        parameters.use_extra_bufts = memoryPolicy.allowWeightRepacking
        guard let pointer = autoreleasepool(invoking:{llama_model_load_from_file(url.path,parameters)}) else { throw GenerationError.invalidModel }
        let owned = NativeModel(pointer)
        try Task.checkCancellation()
        model = owned
    }
    func unload() { model = nil }
    func preferCPUForMemoryPressure() {model=nil;preferCPU=true}
    func generate(_ request: GenerationRequest) throws -> GenerationResult {
        let start = ContinuousClock.now
        try load()
        let loadSeconds = seconds(start.duration(to: .now))
        guard let model else { throw GenerationError.missingModel }
        // At most two attempts; retry changes only the seed and retains all request constraints.
        for attempt in 0..<2 {
            try Task.checkCancellation()
            // llama reserves UINT32_MAX for nondeterministic seeding; map it deterministically.
            let effectiveSeed = UInt32((UInt64(request.seed) + UInt64(attempt)) % UInt64(UInt32.max))
            let elapsedBeforeAttempt = seconds(start.duration(to: .now))
            let output = try autoreleasepool {try infer(model:model.pointer,request:request,seed:effectiveSeed)}
            do {
                let clean: String
                if let task = request.aggressiveTask {
                    if task.repair == nil {
                        let draft=try AggressiveDraft.decodeRetainingSource(output.text)
                        clean=String(decoding:try JSONEncoder().encode(draft),as:UTF8.self)
                    }
                    else { _ = try JSONDecoder().decode([AggressiveRepairTarget].self,from:Data(output.text.utf8)); clean=output.text.trimmingCharacters(in:.whitespacesAndNewlines) }
                }
                else if let translation = request.readingTranslation {
                    _ = try translation.translation(from:output.text); clean = output.text.trimmingCharacters(in:.whitespacesAndNewlines)
                }
                else if let sense = request.senseSelection {
                    _ = try sense.selection(output.text); clean = output.text.trimmingCharacters(in:.whitespacesAndNewlines)
                }
                else if let practice = request.vocabularyPractice { clean = try VocabularyPracticeValidator.validate(output.text, request: practice) }
                else {
                    clean = try PassageValidator.validate(output.text, requestedWords: request.wordCount, genre: request.genre)
                }
                if request.aggressiveTask == nil && request.readingTranslation == nil { try PassageNoveltyValidator.validate(clean, previous: request.previousPassages) }
                return GenerationResult(englishText: clean, duration: seconds(start.duration(to: .now)), modelIdentifier: descriptor.identifier,
                    seed: request.seed, tokenCount: output.tokens, metadata: [
                        "runtime": "llama.cpp-b11829", "modelRevision": descriptor.revision,
                        "modelSHA256": descriptor.sha256, "attempts": String(attempt + 1),
                        "effectiveSeed": String(effectiveSeed), "contextWindow": String(request.configuration.contextWindow),
                        "timeToFirstTokenSeconds": String(elapsedBeforeAttempt + output.firstTokenSeconds),
                        "modelLoadSeconds": String(loadSeconds), "thinking": "disabled",
                        "contextPolicy": "fresh-per-attempt", "scenarioID": request.scenario.map { String($0.id) } ?? "none",
                        "writingGenre": request.genre.rawValue,
                        "formatConstraint": request.outputGrammar == nil ? "prose" : "grammar",
                        "outputLanguage": request.readingTranslation?.languageCode ?? request.vocabularyPractice?.languageCode ?? "en",
                        "aggressiveIntensity": request.aggressiveDomains.isEmpty ? "none" : "extreme",
                        "noveltyHistoryCount": String(request.previousPassages.count),
                        "wordCount": String(clean.split(whereSeparator: \.isWhitespace).count), "contentSource": "local-model",
                        "allocatedContextWindow":String(output.contextWindow),"microBatchSize":String(output.microBatchSize),
                        "gpuLayers":String(memoryPolicy.gpuLayers),"memoryPolicy":memoryPolicy.constrained ? (memoryPolicy.gpuLayers>0 ? "bounded-metal-mmap":"cpu-mmap-fallback"):"default",
                        "offloadKVCache":String(memoryPolicy.offloadCaches),
                        "sampledPeakFootprintBytes":String(output.sampledFootprint)
                    ])
            } catch let error as GenerationError { if attempt == 1 { throw error } }
        }
        throw GenerationError.invalidOutput("retry limit reached")
    }

    private func infer(model: OpaquePointer, request: GenerationRequest, seed: UInt32) throws -> (text: String, tokens: Int, firstTokenSeconds: Double,contextWindow:Int,microBatchSize:Int,sampledFootprint:UInt64) {
        let start = ContinuousClock.now
        guard let vocab = llama_model_get_vocab(model) else { throw GenerationError.invalidModel }
        let config = request.configuration
        let prompt = request.chatPrompt
        let needed = llama_tokenize(vocab, prompt, Int32(prompt.utf8.count), nil, 0, true, true)
        guard needed < 0, needed != Int32.min else { throw GenerationError.decodeFailure }
        let allocatedContext=try memoryPolicy.contextWindow(promptTokens:Int(-needed),maximumTokens:config.maximumTokens,requested:config.contextWindow)
        let microBatch=min(config.batchSize,memoryPolicy.microBatchLimit)
        var sampledFootprint=InferenceProcessMemory.footprint()
        var contextParameters = llama_context_default_params()
        contextParameters.n_ctx = UInt32(allocatedContext)
        contextParameters.n_batch = UInt32(config.batchSize)
        contextParameters.n_ubatch = UInt32(microBatch)
        if memoryPolicy.constrained {
            contextParameters.offload_kqv=memoryPolicy.offloadCaches
            contextParameters.op_offload=false
        }
        let threads = Int32(max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 2)))
        contextParameters.n_threads = threads; contextParameters.n_threads_batch = threads
        guard let context = llama_init_from_model(model, contextParameters) else { throw GenerationError.contextFailure }
        defer { llama_free(context) }
        sampledFootprint=max(sampledFootprint,InferenceProcessMemory.footprint())
        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else { throw GenerationError.contextFailure }
        defer { llama_sampler_free(sampler) }
        if let grammar = request.outputGrammar {
            guard let constraint = llama_sampler_init_grammar(vocab, grammar, "root") else {
                throw GenerationError.invalidOutput("literary format could not be initialized")
            }
            llama_sampler_chain_add(sampler, constraint)
        }
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(config.topP, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_penalties(llama_vocab_n_tokens(vocab), 64, config.repetitionPenalty, 0, 0))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(config.temperature))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(seed))

        var tokens = [llama_token](repeating: 0, count: Int(-needed))
        let count = llama_tokenize(vocab, prompt, Int32(prompt.utf8.count), &tokens, Int32(tokens.count), true, true)
        guard count > 0, Int(count) + config.maximumTokens <= config.contextWindow else { throw GenerationError.contextFailure }
        for offset in stride(from: 0, to: Int(count), by: config.batchSize) {
            try Task.checkCancellation()
            let length = min(config.batchSize, Int(count) - offset)
            let result = tokens.withUnsafeMutableBufferPointer { buffer in
                llama_decode(context, llama_batch_get_one(buffer.baseAddress!.advanced(by: offset), Int32(length)))
            }
            guard result == 0 else { throw GenerationError.decodeFailure }
            sampledFootprint=max(sampledFootprint,InferenceProcessMemory.footprint())
        }
        var bytes = [UInt8](), generated = 0, firstTokenSeconds = 0.0
        for _ in 0..<config.maximumTokens {
            try Task.checkCancellation()
            var token = llama_sampler_sample(sampler, context, -1) // sample also accepts the token into sampler history
            if llama_vocab_is_eog(vocab, token) { break }
            if generated == 0 {
                firstTokenSeconds = seconds(start.duration(to: .now))
            }
            var piece = [CChar](repeating: 0, count: 256)
            var size = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            if size < 0 {
                guard size != Int32.min, -size <= 65536 else { throw GenerationError.decodeFailure }
                piece = [CChar](repeating: 0, count: Int(-size))
                size = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            }
            guard size >= 0 else { throw GenerationError.decodeFailure }
            // Accumulate bytes across token boundaries; token pieces can split a Unicode scalar.
            bytes.append(contentsOf: piece.prefix(Int(size)).map { UInt8(bitPattern: $0) })
            generated += 1
            if generated.isMultiple(of:16) {sampledFootprint=max(sampledFootprint,InferenceProcessMemory.footprint())}
            try Task.checkCancellation()
            let status = withUnsafeMutablePointer(to: &token) { llama_decode(context, llama_batch_get_one($0, 1)) }
            guard status == 0 else { throw GenerationError.decodeFailure }
        }
        guard let text = String(bytes: bytes, encoding: .utf8) else { throw GenerationError.invalidOutput("invalid Unicode") }
        return (text,generated,firstTokenSeconds,allocatedContext,microBatch,sampledFootprint)
    }
}

private func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}
