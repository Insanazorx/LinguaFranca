import Foundation
import LinguaFrancaCore

/// One inference job at a time. Switching modes releases the other model before allocation.
public actor ModeGenerationService: TextGenerationService, ContextualSenseSelecting {
    private let balanced: LlamaCppService
    private let aggressive: LlamaCppService
    private var active=false
    private var unloading=false
    public init(balancedURL:URL?,aggressiveURL:URL?) {
        balanced = .init(modelURL:balancedURL)
        aggressive = .init(modelURL:aggressiveURL,model:.aggressive)
    }
    public func loadModel() async throws { /* Models load lazily after mode selection. */ }
    public func generate(request:GenerationRequest) async throws -> GenerationResult {
        guard !active, !unloading else { throw GenerationError.busy }
        active=true; defer { active=false }
        if request.aggressiveTask != nil || request.readingTranslation != nil {
            await balanced.unloadModel(); try Task.checkCancellation()
            return try await aggressive.generate(request:request)
        }
        await aggressive.unloadModel(); try Task.checkCancellation()
        return try await balanced.generate(request:request)
    }
    public func selectSense(_ request:ContextualSenseRequest) async throws -> Int? {
        guard !active, !unloading else { throw GenerationError.busy }
        active=true; defer { active=false }
        await aggressive.unloadModel(); try Task.checkCancellation()
        return try await balanced.selectSense(request)
    }
    public func cancelGeneration() async { await balanced.cancelGeneration(); await aggressive.cancelGeneration() }
    public func unloadModel() async {
        guard !unloading else { return }
        unloading=true; defer { unloading=false }
        await balanced.unloadModel(); await aggressive.unloadModel()
    }
    /// Keep the 2B model only for the duration of a complete user action on small phones.
    public func releaseIdleAggressiveModel() async {
        guard !active,!unloading,InferenceMemoryPolicy.current(modelBytes:BundledModel.aggressive.byteCount).constrained else{return}
        await aggressive.unloadModel()
    }
    public func preferCPUForMemoryPressure() async {
        await unloadModel()
        await aggressive.preferCPUForMemoryPressure()
    }
}
