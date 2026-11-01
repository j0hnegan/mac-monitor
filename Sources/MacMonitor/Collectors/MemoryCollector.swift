import Darwin
import Foundation

struct MemoryReading {
    enum Pressure { case normal, warn, critical }

    let total: UInt64
    let used: UInt64
    let compressed: UInt64
    let cached: UInt64
    let swapUsed: UInt64
    let pressure: Pressure
}

enum MemoryCollector {
    static func read() -> MemoryReading {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(machHost, HOST_VM_INFO64, $0, &count)
            }
        }

        let page = UInt64(vm_kernel_page_size)
        // Same breakdown as Activity Monitor: used = app memory + wired + compressed.
        let appMemory = UInt64(stats.internal_page_count) - UInt64(stats.purgeable_count)
        let compressed = UInt64(stats.compressor_page_count) * page

        let pressure: MemoryReading.Pressure
        switch sysctl("kern.memorystatus_vm_pressure_level", as: Int32.self) {
        case 4: pressure = .critical
        case 2: pressure = .warn
        default: pressure = .normal
        }

        return MemoryReading(
            total: ProcessInfo.processInfo.physicalMemory,
            used: (appMemory + UInt64(stats.wire_count)) * page + compressed,
            compressed: compressed,
            cached: (UInt64(stats.external_page_count) + UInt64(stats.purgeable_count)) * page,
            swapUsed: sysctl("vm.swapusage", as: xsw_usage.self)?.xsu_used ?? 0,
            pressure: pressure
        )
    }
}
