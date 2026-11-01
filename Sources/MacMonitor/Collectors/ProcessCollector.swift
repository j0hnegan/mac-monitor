import Darwin
import Foundation

struct ProcessSample {
    let pid: pid_t
    let name: String
    let path: String
    /// Physical footprint, the "Memory" column in Activity Monitor.
    let memory: UInt64
    /// Fraction of one core since the previous scan (1.0 = 100%, can exceed 1).
    let cpu: Double
}

/// Processes grouped under the `.app` bundle that owns them, so 25 "Comet Helper (Renderer)" read as "Comet".
struct AppGroup: Identifiable {
    let name: String
    let bundleURL: URL?
    let processes: [ProcessSample]

    var id: String { name }
    var memory: UInt64 { processes.reduce(0) { $0 + $1.memory } }
    var cpu: Double { processes.reduce(0) { $0 + $1.cpu } }
}

/// Reads every process owned by this user. Root-owned processes aren't readable without privileges.
final class ProcessCollector {
    private var lastCPUTime: [pid_t: UInt64] = [:]
    private var paths: [pid_t: String] = [:]
    private var lastScan = Date()

    /// rusage CPU times are in Mach absolute time units, not nanoseconds, on Apple Silicon.
    private static let nanosPerTick: Double = {
        var timebase = mach_timebase_info()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom)
    }()

    func read() -> [ProcessSample] {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastScan)
        var pids = [pid_t](repeating: 0, count: 8192)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))

        var cpuTimes: [pid_t: UInt64] = [:]
        var livePaths: [pid_t: String] = [:]
        var samples: [ProcessSample] = []

        for pid in pids.prefix(Int(max(count, 0))) where pid > 0 {
            var usage = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard status == 0, let path = paths[pid] ?? Self.path(of: pid) else { continue }

            let time = UInt64(Double(usage.ri_user_time + usage.ri_system_time) * Self.nanosPerTick)
            var cpu = 0.0
            if let last = lastCPUTime[pid], time >= last, elapsed > 0 {
                cpu = Double(time - last) / 1e9 / elapsed
            }
            cpuTimes[pid] = time
            livePaths[pid] = path
            samples.append(ProcessSample(pid: pid, name: (path as NSString).lastPathComponent, path: path,
                                         memory: usage.ri_phys_footprint, cpu: cpu))
        }

        lastCPUTime = cpuTimes
        paths = livePaths
        lastScan = now
        return samples
    }

    static func group(_ samples: [ProcessSample]) -> [AppGroup] {
        Dictionary(grouping: samples) { sample -> String in
            bundleURL(for: sample.path)?.path ?? sample.name
        }
        .map { key, processes in
            let bundle = bundleURL(for: processes[0].path)
            return AppGroup(name: bundle?.deletingPathExtension().lastPathComponent ?? key,
                            bundleURL: bundle, processes: processes)
        }
    }

    /// The outermost `.app` in the path, so nested helper apps roll up into their parent.
    private static func bundleURL(for path: String) -> URL? {
        guard let range = path.range(of: ".app/") else { return nil }
        return URL(fileURLWithPath: String(path[..<range.lowerBound]) + ".app")
    }

    private static func path(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}
