import FeatureStoreBuilder

/// The result of the `border-scan` command: the cut, and what the audit found.
public struct BorderScanReport: Sendable {
    /// The cut of the area.
    public let cut: CutReport
    /// What the audit found.
    public let audit: BorderAuditReport
    /// The time to build the store and audit it.
    public let auditTime: Duration

    /// Creates a report.
    public init(cut: CutReport, audit: BorderAuditReport, auditTime: Duration) {
        self.cut = cut
        self.audit = audit
        self.auditTime = auditTime
    }

    /// Whether every border way in the area was stored or has a reason not to be.
    public var isClean: Bool { audit.isClean }
}
