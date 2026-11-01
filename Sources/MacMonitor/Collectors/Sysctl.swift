import Darwin

/// Reads a fixed-size sysctl value by name, e.g. `sysctl("vm.swapusage", as: xsw_usage.self)`.
func sysctl<T>(_ name: String, as type: T.Type) -> T? {
    let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
    defer { value.deallocate() }
    var size = MemoryLayout<T>.size
    guard sysctlbyname(name, value, &size, nil, 0) == 0 else { return nil }
    return value.pointee
}

/// `mach_host_self()` allocates a new port right on every call, so share one.
let machHost = mach_host_self()
