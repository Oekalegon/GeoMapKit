import Foundation

/// Moves the styles that were kept on this device into the folder that is shared (the first time iCloud is used).
enum StyleMigration {
    /// What a migration did.
    struct Result: Equatable {
        /// The names of the files that were copied.
        var copied: [String] = []
        /// The names of the files that were left because the target already has a file of that name (the one in the target is kept).
        var kept: [String] = []
        /// The files that could not be copied, with the reason.
        var failed: [String: String] = [:]
    }

    /// Copies every style file (`.json`) of `source` into `target` that `target` does not have. A file is **never overwritten** and nothing is
    /// removed from `source`: the local copy stays as a backup. The same name in both folders keeps the one in `target`, and says so in the result.
    static func copyMissing(from source: URL, to target: URL) -> Result {
        var result = Result()
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: source.path)) ?? [])
            .filter { $0.lowercased().hasSuffix(".json") && !$0.hasPrefix(".") }.sorted()
        for name in names {
            let destination = target.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: destination.path) {
                result.kept.append(name)
                continue
            }
            do {
                try CoordinatedFiles.write(try CoordinatedFiles.read(source.appendingPathComponent(name)), to: destination)
                result.copied.append(name)
            } catch {
                result.failed[name] = error.localizedDescription
            }
        }
        return result
    }
}
