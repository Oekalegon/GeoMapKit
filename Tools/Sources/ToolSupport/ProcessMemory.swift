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
}
