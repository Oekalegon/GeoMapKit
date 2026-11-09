import Foundation

/// The block files that are open, at most `limit`: the one least recently used is closed first. Thread safe.
final class BlockCache: @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var files: [Int: FeatureStoreFile] = [:]
    private var order: [Int] = []

    init(limit: Int) { self.limit = limit }

    var count: Int { lock.lock(); defer { lock.unlock() }; return files.count }

    func file(for key: Int) -> FeatureStoreFile? {
        lock.lock(); defer { lock.unlock() }
        guard let file = files[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return file
    }

    func store(_ file: FeatureStoreFile, for key: Int) {
        lock.lock(); defer { lock.unlock() }
        if files.updateValue(file, forKey: key) == nil { order.append(key) } else { order.removeAll { $0 == key }; order.append(key) }
        while files.count > limit, let oldest = order.first {
            order.removeFirst()
            files[oldest] = nil
        }
    }
}
