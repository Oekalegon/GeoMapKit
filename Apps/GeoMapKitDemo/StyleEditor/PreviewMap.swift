import GeoCore
import MapUI

/// What the preview of the editor shows: the map that is open, where the map is.
struct PreviewMap {
    let opened: OpenedMap
    let center: Coordinate
    let zoom: Double
}
