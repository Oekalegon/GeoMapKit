import Foundation

/// Memory use of the running process.
public enum ProcessMemory {
    /// The peak resident set size so far, in bytes.
    ///
    /// Resident memory counts the pages of a memory-mapped file that were touched,
    /// so it includes file data that the system can drop again; it is an upper
    /// bound on what the process needs.
    public static func peakResidentBytes() -> Int64 {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        // macOS reports bytes (Linux reports kilobytes).
        #if os(macOS)
        return Int64(usage.ru_maxrss)
        #else
        return Int64(usage.ru_maxrss) * 1024
        #endif
    }

    /// The peak physical footprint so far, in bytes, or `nil` where it is unavailable.
    ///
    /// The footprint counts memory the process has dirtied (its heap), not clean
    /// pages of a memory-mapped file, so it is a better measure of what the cut
    /// itself needs than ``peakResidentBytes()``.
    public static func peakFootprintBytes() -> Int64? {
        #if os(macOS)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Int64(info.ledger_phys_footprint_peak)
        #else
        return nil
        #endif
    }
}
