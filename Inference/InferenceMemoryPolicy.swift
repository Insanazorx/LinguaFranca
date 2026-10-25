import Foundation
import Darwin
import LinguaFrancaCore

enum InferencePlatform:Sendable {case iOSDevice,simulator,mac}

/// Bound the Metal working set on 4 GB phones; keep remaining weights file-backed.
struct InferenceMemoryPolicy:Sendable {
    let constrained:Bool
    let gpuLayers:Int32
    let microBatchLimit:Int
    let allowWeightRepacking:Bool
    let offloadCaches:Bool

    init(platform:InferencePlatform,physicalMemory:UInt64,modelBytes:Int64,preferCPU:Bool=false) {
        constrained = platform == .iOSDevice && physicalMemory<=4*1024*1024*1024 && modelBytes>=1_000_000_000
        gpuLayers = platform == .simulator ? 0:constrained ? (preferCPU ? 0:16):99
        microBatchLimit = constrained ? 16:64
        allowWeightRepacking = !constrained
        offloadCaches = !constrained || gpuLayers>0
    }
    static func current(modelBytes:Int64,preferCPU:Bool=false) -> Self {
        #if targetEnvironment(simulator)
        let platform=InferencePlatform.simulator
        #elseif os(iOS)
        let platform=InferencePlatform.iOSDevice
        #else
        let platform=InferencePlatform.mac
        #endif
        return .init(platform:platform,physicalMemory:ProcessInfo.processInfo.physicalMemory,modelBytes:modelBytes,preferCPU:preferCPU)
    }
    func contextWindow(promptTokens:Int,maximumTokens:Int,requested:Int) throws -> Int {
        let (required,overflow)=promptTokens.addingReportingOverflow(maximumTokens)
        guard promptTokens>0,maximumTokens>0,!overflow,(512...4096).contains(requested),required<=requested else {throw GenerationError.contextFailure}
        guard constrained else {return requested}
        return min(requested,max(512,((required+255)/256)*256))
    }
}

public enum InferenceProcessMemory {
    /// A sample of the current process's accounted footprint, not the system-wide peak.
    public static func footprint() -> UInt64 {
        var info=task_vm_info_data_t()
        var count=mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size/MemoryLayout<integer_t>.size)
        let status=withUnsafeMutablePointer(to:&info) { pointer in
            pointer.withMemoryRebound(to:integer_t.self,capacity:Int(count)) {
                task_info(mach_task_self_,task_flavor_t(TASK_VM_INFO),$0,&count)
            }
        }
        return status == KERN_SUCCESS ? info.phys_footprint:0
    }
    public static func remainingBudget() -> UInt64? {
        #if os(iOS) && !targetEnvironment(simulator)
        return UInt64(os_proc_available_memory())
        #else
        return nil
        #endif
    }
    /// A warning can request cache trimming while the active task still has ample headroom.
    /// Kernel-critical pressure always interrupts; unknown/low budgets remain conservative.
    public static func shouldInterrupt(critical:Bool,footprint:UInt64,remainingBudget:UInt64?) -> Bool {
        if critical {return true}
        guard let remainingBudget else {return true}
        return remainingBudget<256*1024*1024 || footprint>=1280*1024*1024
    }
}
