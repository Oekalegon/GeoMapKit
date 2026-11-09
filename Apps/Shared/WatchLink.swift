import FeatureStore
import Foundation
import Observation

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// The state of the link between the iPhone and the Watch, for the screens of either app.
enum WatchLinkStatus: Equatable, Sendable {
    /// There is no Watch to talk to (the Mac, or a device that does not support it).
    case unsupported
    /// The session is not active yet.
    case starting
    /// On the phone: no Watch is paired.
    case notPaired
    /// On the phone: the Watch has no copy of this app.
    case appNotInstalled
    /// Files can be sent (on the phone) or received (on the Watch).
    case ready

    var sentence: String {
        switch self {
        case .unsupported: "This device has no Apple Watch."
        case .starting: "Connecting to the Watch…"
        case .notPaired: "No Apple Watch is paired."
        case .appNotInstalled: "The app is not installed on the Watch."
        case .ready: "Ready to send to the Watch."
        }
    }
}

/// Why a map could not be sent.
enum WatchSendError: Error, Equatable, LocalizedError {
    case notReady(WatchLinkStatus)
    case tooLarge(bytes: Int64, limit: Int64)
    case notAMap(String)

    var errorDescription: String? {
        switch self {
        case .notReady(let status): status.sentence
        case .notAMap(let reason): "The file is not a map that can be sent: \(reason)"
        case .tooLarge(let bytes, let limit):
            "The map is \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)), more than the Watch gets "
                + "(\(ByteCountFormatter.string(fromByteCount: limit, countStyle: .file))). Cut a smaller area for the Watch."
        }
    }
}

/// The link to the other device by WatchConnectivity: the phone sends map files, the Watch receives them.
///
/// Files go by `transferFile`, which the system queues and delivers in the background, also when the app is not running. The phone
/// checks the whole file and sends a copy of it (so removing the map from the library cannot break a transfer on the way; the
/// copy is deleted when the transfer is done). The Watch moves each file into its ``WatchMapStore`` while the delegate call runs
/// (the system deletes the file after it). The link starts no location updates and no timers.
@MainActor
@Observable
final class WatchLink: NSObject {
    /// The most bytes a map may have to be sent. A Watch copy of 16 cells is about 1.4 MB; provisional, until the Watch storage
    /// ceiling is known (question 39).
    static let sendLimit: Int64 = 20_000_000

    private(set) var status: WatchLinkStatus = .unsupported
    /// Files that are on their way (on the phone).
    private(set) var pending = 0
    /// What went wrong at the last send or receive, as a sentence.
    private(set) var lastProblem: String?
    /// Counts every map that arrived (on the Watch), so that a screen reads the store again.
    private(set) var received = 0

    nonisolated let store: WatchMapStore

    init(store: WatchMapStore = .standard) {
        self.store = store
        super.init()
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        status = .starting
        WCSession.default.delegate = self
        WCSession.default.activate()
        #endif
    }

    /// Sends a map file to the Watch.
    ///
    /// The file is read completely first (checksum and cells), then copied for the transfer. A transfer of a map with the same
    /// name that is still on the way is cancelled, since the Watch would replace it anyway.
    ///
    /// - Parameters:
    ///   - url: The `.gmk` file.
    ///   - name: The name the Watch shows.
    /// - Throws: ``WatchSendError`` if the link is not ready, the file is too big or is not a map; file errors if the copy fails.
    func send(_ url: URL, named name: String) throws {
        guard status == .ready else { throw WatchSendError.notReady(status) }
        let bytes = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        guard bytes <= Self.sendLimit else { throw WatchSendError.tooLarge(bytes: bytes, limit: Self.sendLimit) }
        do {
            try FeatureStoreFile(contentsOf: url).verify()
        } catch {
            throw WatchSendError.notAMap("\(error)")
        }
        #if os(iOS) && canImport(WatchConnectivity)
        let session = WCSession.default
        for transfer in session.outstandingFileTransfers where (transfer.file.metadata?["name"] as? String) == name {
            transfer.cancel()
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WatchOutbox-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent(WatchMapStore.fileName(for: name))
        try FileManager.default.copyItem(at: url, to: copy)
        session.transferFile(copy, metadata: ["name": name])
        pending = session.outstandingFileTransfers.count
        lastProblem = nil
        #endif
    }

    /// Reads the state of the session again; what a delegate call reports may be old by the time it gets here.
    fileprivate func refresh(problem: String? = nil) {
        #if canImport(WatchConnectivity)
        status = Self.status(of: WCSession.default)
        #endif
        if let problem { lastProblem = problem }
    }

    fileprivate func finished(pending: Int, problem: String?) {
        self.pending = pending
        if let problem { lastProblem = problem }
    }

    fileprivate func arrived(problem: String?) {
        if let problem { lastProblem = problem } else { lastProblem = nil; received += 1 }
    }
}

#if canImport(WatchConnectivity)
extension WatchLink: WCSessionDelegate {
    nonisolated private static func status(of session: WCSession) -> WatchLinkStatus {
        guard session.activationState == .activated else { return .starting }
        #if os(iOS)
        if !session.isPaired { return .notPaired }
        if !session.isWatchAppInstalled { return .appNotInstalled }
        #endif
        return .ready
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let problem = error.map { "The link to the Watch could not start: \($0.localizedDescription)" }
        Task { @MainActor in self.refresh(problem: problem) }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // After a switch to another Watch: activate again for the new one.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let pending = session.outstandingFileTransfers.count
        // The copy made for the transfer is not needed any more.
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL.deletingLastPathComponent())
        // A transfer that was cancelled because a newer copy replaces it is no problem.
        let problem = fileTransfer.progress.isCancelled ? nil : error.map { "The map could not be sent to the Watch: \($0.localizedDescription)" }
        Task { @MainActor in self.finished(pending: pending, problem: problem) }
    }
    #endif

    #if os(watchOS)
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // The file is deleted when this call returns: it is checked and moved here.
        let name = (file.metadata?["name"] as? String) ?? file.fileURL.lastPathComponent
        let store = self.store
        let problem: String?
        do {
            try store.accept(file.fileURL, named: name, fullCheck: false)
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
        Task { @MainActor in self.arrived(problem: problem) }
    }
    #endif
}
#endif
