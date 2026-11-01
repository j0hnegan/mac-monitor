import Darwin
import Foundation

struct DiskReading {
    let free: Int64
    let total: Int64
}

final class DiskCollector {
    private var cached: DiskReading?
    private var readAt = Date.distantPast

    /// Free space including purgeable files, matching Finder. That query is a ~40 ms round trip
    /// to the CacheDelete daemon and free space moves slowly, so re-read it at most every 5 minutes.
    func read() -> DiskReading? {
        guard Date().timeIntervalSince(readAt) > 300 else { return cached }
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        if let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: keys),
           let free = values.volumeAvailableCapacityForImportantUsage,
           let total = values.volumeTotalCapacity {
            cached = DiskReading(free: free, total: Int64(total))
        }
        readAt = Date()
        return cached
    }
}

enum UptimeCollector {
    static func read() -> TimeInterval {
        guard let boot = sysctl("kern.boottime", as: timeval.self) else { return 0 }
        return Date().timeIntervalSince1970 - TimeInterval(boot.tv_sec)
    }
}
