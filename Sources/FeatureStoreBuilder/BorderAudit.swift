import FeatureStore
import GeoCore
import OSMPBF

/// Checks that the builder keeps the borders between countries: every way of a national border relation (`boundary=administrative`,
/// `admin_level=2`) that lies in the stored area is stored as `countryBorder`, or has a reason not to be one.
///
/// A border is mapped in several ways (tagged ways, untagged ways that only the relation says are a border, rivers, lines in the sea),
/// and each has been lost to a rule that was meant for something else. The audit finds the next one on real data. It does not find a
/// border that no relation holds, or a relation that is missing from the extract.
public enum BorderAudit {
    /// Builds the store of an extract and audits it.
    ///
    /// - Parameters:
    ///   - extract: The extract, cut from the files of the area to look at.
    ///   - maxExamples: How many example ways to keep for each group of unexpected ways.
    /// - Returns: The report.
    /// - Throws: What the builder or the store reader throws.
    public static func run(on extract: OSMExtract, maxExamples: Int = 3) throws -> BorderAuditReport {
        let file = try FeatureStoreFile(data: try FeatureStoreBuilder().build(from: extract).data)
        var stored = Set<Int64>()
        for cell in try file.cells() {
            for band in ZoomBand.allCases {
                for feature in try file.features(in: cell, band: band)
                where feature.classID == FeatureClass.countryBorder.rawValue && feature.objectType == .way {
                    stored.insert(feature.objectID)
                }
            }
        }
        return audit(extract, stored: stored, maxExamples: maxExamples)
    }

    /// Audits an extract against the ways that were stored as `countryBorder`.
    ///
    /// - Parameters:
    ///   - extract: The extract. Its bounding box is the stored area.
    ///   - stored: The ids of the ways that are stored as `countryBorder`.
    ///   - maxExamples: How many example ways to keep for each group.
    /// - Returns: The report.
    public static func audit(_ extract: OSMExtract, stored: Set<Int64>, maxExamples: Int = 3) -> BorderAuditReport {
        let classifier = FeatureClassifier()
        var relationsOfWay: [Int64: Set<String>] = [:]
        for position in extract.relations.indices {
            let tags = extract.relations.tags(at: position)
            guard tags.value(forKey: "boundary") == "administrative", tags.value(forKey: "admin_level") == "2",
                tags.value(forKey: "type") == "boundary" || tags.value(forKey: "type") == "multipolygon"
            else { continue }
            let name = tags.value(forKey: "name:en") ?? tags.value(forKey: "name") ?? "relation \(extract.relations.ids[position])"
            for member in extract.relations[position].relation.members where member.type == .way {
                relationsOfWay[member.id, default: []].insert(name)
            }
        }

        var report = BorderAuditReport()
        report.memberWays = relationsOfWay.count
        var groups: [String: BorderAuditReport.Group] = [:]
        for (wayID, relations) in relationsOfWay.sorted(by: { $0.key < $1.key }) {
            guard let position = Self.position(ofWay: wayID, in: extract.ways) else {
                report.notInExtract += 1
                continue
            }
            if stored.contains(wayID) {
                report.stored += 1
                continue
            }
            // The extract keeps all of a relation's ways, far outside the cut; only what lies in the stored area counts.
            guard extract.ways.nodeIDs(at: position).contains(where: { id in
                extract.node(withID: id).map { extract.boundingBox.contains($0.coordinate) } ?? false
            }) else {
                report.outsideStoredArea += 1
                continue
            }
            let tags = extract.ways.tags(at: position)
            if tags.value(forKey: "natural") == "coastline" {
                report.expected[.coastline, default: 0] += 1
            } else if relations.count == 1, classifier.isSeaLimit(tags) {
                report.expected[.limitOfOneCountry, default: 0] += 1
            } else {
                var parts = ["\(relations.count) relation\(relations.count == 1 ? "" : "s")"]
                for key in signatureKeys { if let value = tags.value(forKey: key) { parts.append("\(key)=\(value)") } }
                if tags.orderedTags.isEmpty { parts.append("no tags") }
                let signature = parts.joined(separator: " ")
                var group = groups[signature] ?? BorderAuditReport.Group(signature: signature, count: 0, examples: [])
                group.count += 1
                if group.examples.count < maxExamples {
                    group.examples.append(BorderAuditReport.Example(wayID: wayID, relations: relations.sorted()))
                }
                groups[signature] = group
            }
        }
        report.unexpected = groups.values.sorted { ($0.count, $1.signature) > ($1.count, $0.signature) }
        return report
    }

    /// The tags that tell groups of ways apart in the report.
    private static let signatureKeys = [
        "boundary", "admin_level", "border_type", "maritime", "natural", "waterway", "highway", "railway", "place", "landuse", "leisure",
    ]

    /// The position of a way in the extract, which holds its ways sorted by id.
    private static func position(ofWay id: Int64, in ways: ExtractedWays) -> Int? {
        var low = 0, high = ways.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let found = ways.ids[middle]
            if found == id { return middle }
            if found < id { low = middle + 1 } else { high = middle - 1 }
        }
        return nil
    }
}
