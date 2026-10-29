import Foundation
import Darwin
import IOKit.ps

public final class SystemSampler {
    private var previous: [UInt64]?
    private var lastDate: Date?
    public init() {}
    public func sample() -> SystemSample {
        var info = host_cpu_load_info(); var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size) } }
        let now = Date(); var cpu: Double?
        if result == KERN_SUCCESS {
            let ticks = [UInt64(info.cpu_ticks.0), UInt64(info.cpu_ticks.1), UInt64(info.cpu_ticks.2), UInt64(info.cpu_ticks.3)]
            if let old = previous, let lastDate, now.timeIntervalSince(lastDate) < 60, zip(ticks, old).allSatisfy({ $0 >= $1 }) {
                let delta = zip(ticks, old).map(-); let total = delta.reduce(0, +)
                if total > 0 { cpu = 100 * Double(total - delta[2]) / Double(total) }
            }
            previous = ticks; lastDate = now
        }
        var vm = vm_statistics64(); var vmSize = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vm) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmSize)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmSize) } }
        let page = Double(vm_kernel_page_size)
        // App memory (internal minus purgeable), wired memory, and compressed memory.
        let app = max(0, Double(vm.internal_page_count) - Double(vm.purgeable_count))
        let memory = vmResult == KERN_SUCCESS ? (app + Double(vm.wire_count) + Double(vm.compressor_page_count)) * page : -1
        var battery: Double?; var charging = false; var ac = false
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                guard let d = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any], d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
                if let current = d[kIOPSCurrentCapacityKey] as? Double, let max = d[kIOPSMaxCapacityKey] as? Double, max > 0 { battery = min(100, Swift.max(0, current / max * 100)) }
                charging = d[kIOPSIsChargingKey] as? Bool ?? false
                ac = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            }
        }
        return SystemSample(date: now, cpu: cpu, memoryUsed: memory, memoryTotal: Double(ProcessInfo.processInfo.physicalMemory), compressed: Double(vm.compressor_page_count) * page, battery: battery, charging: charging, onAC: ac)
    }
}
