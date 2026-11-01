import Darwin
import Foundation

struct CPUReading {
    /// Busy fraction (0–1) since the previous sample.
    let current: Double
    /// Busy fraction over the full sustained window, or nil until the window has filled.
    let sustained: Double?
}

final class CPUCollector {
    private struct Ticks {
        let busy: UInt64
        let total: UInt64

        func busyFraction(since earlier: Ticks) -> Double {
            let total = self.total - earlier.total
            return total == 0 ? 0 : Double(busy - earlier.busy) / Double(total)
        }
    }

    private var history: [(date: Date, ticks: Ticks)] = []

    init() {
        history.append((Date(), Self.ticks()))
    }

    func read(window: TimeInterval) -> CPUReading {
        let now = Date()
        let ticks = Self.ticks()
        let current = ticks.busyFraction(since: history[history.count - 1].ticks)

        history.append((now, ticks))
        // Keep the newest sample that's at least `window` old as the baseline, plus everything after it.
        if let baseline = history.lastIndex(where: { now.timeIntervalSince($0.date) >= window }) {
            history.removeFirst(baseline)
        }
        let oldest = history[0]
        let sustained = now.timeIntervalSince(oldest.date) >= window ? ticks.busyFraction(since: oldest.ticks) : nil

        return CPUReading(current: current, sustained: sustained)
    }

    private static func ticks() -> Ticks {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(machHost, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        let user = UInt64(load.cpu_ticks.0), system = UInt64(load.cpu_ticks.1)
        let idle = UInt64(load.cpu_ticks.2), nice = UInt64(load.cpu_ticks.3)
        return Ticks(busy: user + system + nice, total: user + system + idle + nice)
    }
}
