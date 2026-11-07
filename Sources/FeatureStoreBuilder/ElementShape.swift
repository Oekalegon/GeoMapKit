/// The shape of the OSM object being classified. It decides whether the result is a point, a line or an area.
public enum ElementShape: Sendable {
    /// A tagged node.
    case node
    /// A way whose first and last node differ.
    case openWay
    /// A way whose first and last node are the same.
    case closedWay
    /// An assembled `type=multipolygon` relation.
    case multipolygon
}
