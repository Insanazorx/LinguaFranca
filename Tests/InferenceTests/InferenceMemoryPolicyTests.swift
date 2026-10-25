import Testing
import LinguaFrancaCore
@testable import LinguaFrancaInference

@Test func largeModelsUseBoundedMetalAndCanFallBackToCPUOnFourGBPhones() {
    let plan=InferenceMemoryPolicy(platform:.iOSDevice,physicalMemory:4*1024*1024*1024,modelBytes:BundledModel.aggressive.byteCount)
    #expect(plan.constrained && plan.gpuLayers==16)
    #expect(!plan.allowWeightRepacking && plan.offloadCaches)
    #expect(plan.microBatchLimit==16)
    let fallback=InferenceMemoryPolicy(platform:.iOSDevice,physicalMemory:4*1024*1024*1024,modelBytes:BundledModel.aggressive.byteCount,preferCPU:true)
    #expect(fallback.gpuLayers==0 && !fallback.offloadCaches && !fallback.allowWeightRepacking)
}

@Test func balancedMacAndLargerDevicesRetainTheirExistingAcceleration() {
    for (platform,memory,model) in [(InferencePlatform.iOSDevice,UInt64(4*1024*1024*1024),BundledModel.qwen35),(.iOSDevice,8*1024*1024*1024,.aggressive),(.mac,4*1024*1024*1024,.aggressive)] {
        let plan=InferenceMemoryPolicy(platform:platform,physicalMemory:memory,modelBytes:model.byteCount)
        #expect(!plan.constrained && plan.gpuLayers==99 && plan.microBatchLimit==64)
    }
    #expect(InferenceMemoryPolicy(platform:.simulator,physicalMemory:8*1024*1024*1024,modelBytes:BundledModel.aggressive.byteCount).gpuLayers==0)
}

@Test func smallerContextsStillFitEveryPromptAndTheEntireOutputBudget() throws {
    let plan=InferenceMemoryPolicy(platform:.iOSDevice,physicalMemory:4*1024*1024*1024,modelBytes:BundledModel.aggressive.byteCount)
    for prompt in stride(from:1,through:2500,by:31) {
        let context=try plan.contextWindow(promptTokens:prompt,maximumTokens:1536,requested:4096)
        #expect(context>=prompt+1536 && context<=4096)
    }
    #expect(try plan.contextWindow(promptTokens:200,maximumTokens:512,requested:4096)==768)
    #expect(throws:GenerationError.self) {try plan.contextWindow(promptTokens:3000,maximumTokens:1536,requested:4096)}
    #expect(throws:GenerationError.self) {try plan.contextWindow(promptTokens:Int.max,maximumTokens:1536,requested:4096)}
}

@Test func memoryWarningsTrimCachesButCriticalOrLowBudgetPressureInterrupts() {
    let mib:UInt64=1024*1024
    #expect(!InferenceProcessMemory.shouldInterrupt(critical:false,footprint:310*mib,remainingBudget:1000*mib))
    #expect(InferenceProcessMemory.shouldInterrupt(critical:true,footprint:310*mib,remainingBudget:1000*mib))
    #expect(InferenceProcessMemory.shouldInterrupt(critical:false,footprint:310*mib,remainingBudget:128*mib))
    #expect(InferenceProcessMemory.shouldInterrupt(critical:false,footprint:1280*mib,remainingBudget:500*mib))
    #expect(InferenceProcessMemory.shouldInterrupt(critical:false,footprint:310*mib,remainingBudget:nil))
}
