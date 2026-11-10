import Foundation

/// What to do when two devices changed the same style: the newest version wins and the others are kept as copies, so nothing is lost silently.
enum StyleConflictRule {
    /// One version of a style file.
    struct Version: Equatable {
        /// Which version it is: `nil` for the file as it is now, or the identifier of a conflicting version.
        var id: Int?
        /// When it was last changed.
        var modified: Date
    }

    /// The outcome.
    struct Plan: Equatable {
        /// The version that becomes the file.
        var winner: Version
        /// The versions that are saved under a name of their own (`name (conflict …).json`).
        var copies: [Version]
    }

    /// The newest version wins; on a tie the file as it is now wins (a change that was made here stays). Every other version is a copy.
    static func plan(current: Date, conflicts: [(id: Int, modified: Date)]) -> Plan {
        let now = Version(id: nil, modified: current)
        let others = conflicts.map { Version(id: $0.id, modified: $0.modified) }
        let all = [now] + others
        let winner = all.max { ($0.modified, $0.id == nil ? 1 : 0) < ($1.modified, $1.id == nil ? 1 : 0) } ?? now
        return Plan(winner: winner, copies: all.filter { $0 != winner }.sorted { $0.modified > $1.modified })
    }

    /// The name of the copy of a version: `Name (conflict 2026-11-10 16.04).json`, made unique in the folder by a number.
    static func copyName(of file: String, modified: Date, existing: Set<String>) -> String {
        let base = (file as NSString).deletingPathExtension
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        let stem = "\(base) (conflict \(formatter.string(from: modified)))"
        var name = "\(stem).json"
        var number = 2
        while existing.contains(name) {
            name = "\(stem) \(number).json"
            number += 1
        }
        return name
    }
}
