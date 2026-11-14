import FeatureStoreBuilder
import Foundation
import GeoCore
import OSMPBF

extension ToolRunner {
    /// Cuts an area, builds its store and checks that every way of the national border relations in it is stored as a border.
    ///
    /// Nothing is written: the store is built in memory and read back.
    ///
    /// - Parameters:
    ///   - urls: The PBF files, in order of preference (see ``cut(urls:area:options:)``).
    ///   - area: The area to cut. It is widened to whole cells, as `build` does.
    ///   - options: The cutter settings.
    ///   - maxExamples: How many example ways to list for each group of unexpected ways.
    /// - Returns: The cut and the audit.
    /// - Throws: ``ToolError`` for a missing file, or whatever the cutter, builder or store reader throws.
    public static func borderScan(
        urls: [URL], area: BoundingBox, options: AreaCutter.Options = .init(), maxExamples: Int = 3
    ) throws -> BorderScanReport {
        let (extract, cutReport) = try cutExtract(urls: urls, area: FeatureStoreBuilder.cellAlignedBox(covering: area), options: options)
        let clock = ContinuousClock()
        let started = clock.now
        let audit = try BorderAudit.run(on: extract, maxExamples: maxExamples)
        return BorderScanReport(cut: cutReport, audit: audit, auditTime: clock.now - started)
    }
}
