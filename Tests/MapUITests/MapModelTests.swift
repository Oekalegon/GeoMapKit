import FeatureStore
import Foundation
import GeoCore
import MapRender
import MapStyle
import Testing

@testable import MapUI

@MainActor
@Suite("MapModel")
struct MapModelTests {
    /// A store with one road in one cell.
    private func file() throws -> (FeatureStoreFile, Coordinate) {
        var writer = FeatureStoreWriter(
            boundingBox: BoundingBox(south: 47.0, west: 9.4, north: 47.3, east: 9.7), attribution: "© OpenStreetMap contributors, ODbL")
        let cell = try #require(TileID.containing(Coordinate(latitude: 47.1, longitude: 9.5), zoom: 13))
        let centre = Coordinate(
            latitude: (cell.northWest.latitude + cell.southEast.latitude) / 2,
            longitude: (cell.northWest.longitude + cell.southEast.longitude) / 2)
        let lat = Int32((centre.latitude * 1e7).rounded())
        let lon = Int32((centre.longitude * 1e7).rounded())
        let road = GeometryPart(points: [PackedPoint(longitude: lon - 3_000, latitude: lat), PackedPoint(longitude: lon + 3_000, latitude: lat)])
        try writer.add(
            StoredFeature(classID: FeatureClass.roadMajor.rawValue, kind: .line, objectType: .way, objectID: 1, parts: [road]),
            band: .detail, cell: cell)
        return (try FeatureStoreFile(data: try writer.data()), centre)
    }

    private func waitForFrame(_ model: MapModel, differentFrom old: MapViewport? = nil) async throws -> MapFrame {
        for _ in 0..<200 {
            if let frame = model.frame, frame.viewport != old { return frame }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw MapRenderError.noBands
    }

    @Test func drawsAFrameWithAMarginAndKeepsItForASmallPan() async throws {
        let (store, centre) = try file()
        let model = MapModel(file: store, style: .standard)
        let view = MapViewport(center: centre, zoom: 16, width: 200, height: 100)
        model.request(viewport: view, scale: 2, interacting: false)
        let first = try await waitForFrame(model)
        #expect(first.viewport.width == 400 && first.viewport.height == 300)
        #expect(first.image.width == 800 && first.image.height == 600)

        // A pan of 20 points keeps the cached frame.
        let moved = MapViewport(center: view.coordinate(at: ScreenPoint(x: 120, y: 50)), zoom: 16, width: 200, height: 100)
        model.request(viewport: moved, scale: 2, interacting: false)
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.frame?.viewport == first.viewport)

        // A zoom change after the gesture draws a new frame.
        model.request(viewport: MapViewport(center: centre, zoom: 17, width: 200, height: 100), scale: 2, interacting: false)
        let zoomed = try await waitForFrame(model, differentFrom: first.viewport)
        #expect(zoomed.viewport.zoom == 17)
    }

    @Test func aPanPastHalfTheMarginDrawsTheNextFrameBeforeTheEdgeShows() async throws {
        let (store, centre) = try file()
        let model = MapModel(file: store, style: .standard)
        let view = MapViewport(center: centre, zoom: 16, width: 200, height: 100)
        model.request(viewport: view, scale: 1, interacting: true)
        let first = try await waitForFrame(model)
        // The margin is 100 points, so the limit is 50. Move 70 points while the gesture is still going: the frame
        // still covers the view, but the next one must start now, not when the edge shows.
        let moved = MapViewport(center: view.coordinate(at: ScreenPoint(x: 170, y: 50)), zoom: 16, width: 200, height: 100)
        #expect(MapFramePlan(frame: first.viewport, requested: moved).coversView)
        model.request(viewport: moved, scale: 1, interacting: true)
        let next = try await waitForFrame(model, differentFrom: first.viewport)
        #expect(abs(next.viewport.center.longitude - moved.center.longitude) < 1e-9)
    }

    @Test func aFrameThatIsOutOfDateWhenItArrivesIsCorrected() async throws {
        let (store, centre) = try file()
        let model = MapModel(file: store, style: .standard)
        let first = MapViewport(center: centre, zoom: 16, width: 200, height: 100)
        // The user has moved on by 3 km before the first frame is ready.
        let later = MapViewport(center: Coordinate(latitude: centre.latitude, longitude: centre.longitude + 0.03), zoom: 16, width: 200, height: 100)
        model.request(viewport: first, scale: 1, interacting: false)
        model.request(viewport: later, scale: 1, interacting: false)
        for _ in 0..<200 {
            if let frame = model.frame, abs(frame.viewport.center.longitude - later.center.longitude) < 1e-9 { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        Issue.record("no frame for the latest viewport arrived")
    }

    @Test func aStyleChangeDropsTheFrame() async throws {
        let (store, centre) = try file()
        let model = MapModel(file: store, style: .standard)
        let view = MapViewport(center: centre, zoom: 16, width: 200, height: 100)
        model.request(viewport: view, scale: 1, interacting: false)
        _ = try await waitForFrame(model)
        model.update(file: store, style: .watch)
        #expect(model.frame == nil)
        model.request(viewport: view, scale: 1, interacting: false)
        let redrawn = try await waitForFrame(model)
        #expect(redrawn.styleID == 1)
    }

    @Test func aViewWithoutAreaDrawsNothing() async throws {
        let (store, centre) = try file()
        let model = MapModel(file: store, style: .standard)
        model.request(viewport: MapViewport(center: centre, zoom: 16, width: 0, height: 100), scale: 1, interacting: false)
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.frame == nil && model.errorDescription == nil)
    }
}
