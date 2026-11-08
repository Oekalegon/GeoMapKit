import Foundation
import GeoCore
import OSMPBF

/// On which side of its member ways a boundary relation lies.
///
/// The way of a border belongs to the relations of the two regions it separates, and the data does not say which region is on
/// which side. The side follows from the course of the relation: its outer ways, taken in order and each in the direction
/// in which the ring runs, make a ring that is closed (or nearly: a few members may be missing from the extract). A ring that
/// runs clockwise has its region on the right of the direction of travel, one that runs counter-clockwise on the left, and
/// the direction of travel along a way against the direction in which the way is stored decides the rest. Relations do not
/// all run the same way round: the national relations of Norway and Sweden run clockwise, the county of Østfold and the
/// country of Liechtenstein counter-clockwise.
enum BoundarySides {
    /// The largest share of the way members that may be missing from the extract for the ring to be judged on what is there.
    static let maximumMissingShare = 0.02
    /// The largest share of the outer ways whose direction of travel may be unknown.
    static let maximumUndirectedShare = 0.1

    /// The side of each member way on which the region lies, looking in the direction of the way as stored.
    ///
    /// - Parameters:
    ///   - relation: The boundary relation.
    ///   - extract: The extract that holds the member ways and their nodes.
    /// - Returns: For each member way whose side is known, `true` if the region is on the right of the way and `false` if it
    ///   is on the left. Empty if the ring cannot be followed: too many ways missing, ways out of order, no area.
    static func regionIsOnRight(of relation: OSMRelation, in extract: OSMExtract) -> [Int64: Bool] {
        struct Member {
            var id: Int64
            var first: Int64
            var last: Int64
            var points: [Coordinate]
        }
        var members: [Member?] = []
        var wayCount = 0, missing = 0
        for member in relation.members where member.type == .way {
            wayCount += 1
            // An inner ring bounds a hole in the region: the region is on the other side of it. Left out, like what is missing.
            guard member.role != "inner" else { members.append(nil); continue }
            guard let index = extract.ways.index(ofID: member.id) else { missing += 1; members.append(nil); continue }
            let ids = extract.ways.nodeIDs(at: index)
            guard let first = ids.first, let last = ids.last, first != last else { members.append(nil); continue }
            let points = ids.compactMap { id in extract.nodes.index(ofID: id).map { extract.nodes.coordinate(at: $0) } }
            guard points.count >= 2 else { missing += 1; members.append(nil); continue }
            members.append(Member(id: member.id, first: first, last: last, points: points))
        }
        guard wayCount > 0, Double(missing) <= Double(wayCount) * maximumMissingShare else { return [:] }

        // The direction in which the ring runs along each way: forward if it leaves the way at its last node, where the next
        // way (or the one before it) is joined.
        var forward = [Bool?](repeating: nil, count: members.count)
        var outerCount = 0, undirected = 0
        for index in members.indices {
            guard let member = members[index] else { continue }
            outerCount += 1
            var votes = 0
            if index + 1 < members.count, let next = members[index + 1] {
                if member.last == next.first || member.last == next.last { votes += 1 }
                if member.first == next.first || member.first == next.last { votes -= 1 }
            }
            if index > 0, let previous = members[index - 1] {
                if member.first == previous.first || member.first == previous.last { votes += 1 }
                if member.last == previous.first || member.last == previous.last { votes -= 1 }
            }
            if votes == 0 { undirected += 1 } else { forward[index] = votes > 0 }
        }
        guard outerCount > 0, Double(undirected) <= Double(outerCount) * maximumUndirectedShare else { return [:] }

        var ring: [Coordinate] = []
        for index in members.indices {
            guard let member = members[index] else { continue }
            ring += forward[index] == false ? member.points.reversed() : member.points
        }
        guard let clockwise = isClockwise(ring) else { return [:] }
        var result: [Int64: Bool] = [:]
        for index in members.indices {
            guard let member = members[index], let isForward = forward[index] else { continue }
            // Clockwise, the region is on the right of the way in the direction of travel: of the way as stored if it is
            // travelled forward, on its left if it is travelled backwards.
            result[member.id] = clockwise == isForward
        }
        return result
    }

    /// Whether a ring, closed by a line from its last point to its first, runs clockwise on the map, or `nil` when it has no
    /// area. Meridians are unrolled, so a ring over the antimeridian does not jump.
    static func isClockwise(_ ring: [Coordinate]) -> Bool? {
        guard ring.count >= 3 else { return nil }
        let meanLatitude = ring.reduce(0) { $0 + $1.latitude } / Double(ring.count)
        let scale = cos(meanLatitude * .pi / 180)
        var points: [(x: Double, y: Double)] = []
        points.reserveCapacity(ring.count)
        var offset = 0.0
        var previous = ring[0].longitude
        for coordinate in ring {
            if coordinate.longitude - previous > 180 { offset -= 360 } else if coordinate.longitude - previous < -180 { offset += 360 }
            previous = coordinate.longitude
            points.append(((coordinate.longitude + offset) * scale, coordinate.latitude))
        }
        var twiceArea = 0.0
        for index in points.indices {
            let a = points[index], b = points[(index + 1) % points.count]
            twiceArea += a.x * b.y - b.x * a.y
        }
        guard twiceArea != 0 else { return nil }
        return twiceArea < 0
    }
}
