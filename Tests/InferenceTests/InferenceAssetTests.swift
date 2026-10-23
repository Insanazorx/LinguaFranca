import Foundation
import Testing
import LinguaFrancaCore
import LinguaFrancaInference

@Test func selectedManifestMatchesVerifiedModelDescriptor() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("Resources/Models/model-manifest.json"))
    let manifest = try JSONDecoder().decode(BundledModel.self, from: data)
    #expect(manifest.identifier == BundledModel.qwen35.identifier)
    #expect(manifest.filename == BundledModel.qwen35.filename)
    #expect(manifest.sha256 == BundledModel.qwen35.sha256)
    #expect(manifest.byteCount == BundledModel.qwen35.byteCount)
}

@Test func missingModelFailsWithoutFallback() async throws {
    let service = LlamaCppService(modelURL: nil)
    await #expect(throws: GenerationError.missingModel) { try await service.loadModel() }
    await #expect(throws: GenerationError.missingModel) {
        try await service.generate(request: GenerationRequest(topic: "Science", seed: 1))
    }
    await service.cancelGeneration()
    await service.unloadModel()
    await service.unloadModel()
}

@Test func corruptAssetIsRejectedBeforeNativeLoad() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gguf")
    try Data("not a model".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let service = LlamaCppService(modelURL: url)
    await #expect(throws: GenerationError.checksumMismatch) { try await service.loadModel() }
    await service.unloadModel()
}

@Test func cancelledCallerDoesNotLoadModel() async {
    let service = LlamaCppService(modelURL: nil)
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await service.generate(request: GenerationRequest(topic: "Culture", seed: 1))
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    await service.unloadModel()
}
