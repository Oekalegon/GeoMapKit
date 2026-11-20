import FeatureStore
import Foundation
import GeoCore
import MapRender
import Observation
import TrackHeatMap
import TrackStorage

/// The heat map on the map, and its time-lapse: what the screen shows and the player that steps through the months.
///
/// What a heat map is (the counts on the ways, the colour scale, the months and their running totals) is the package's
/// (`TrackHeatMap`); this class holds the choices and the frame that is shown, and plays the months at a pace.
@MainActor
@Observable
final class HeatMapModel {
    /// How a time-lapse frame counts the months.
    enum SpanChoice: String, CaseIterable, Identifiable {
        case cumulative = "Up to the month"
        case month = "One month"
        case year = "Twelve months"
        var id: String { rawValue }

        var span: HeatMapTimeLapse.Span {
            switch self {
            case .cumulative: .cumulative
            case .month: .last(months: 1)
            case .year: .last(months: 12)
            }
        }
    }

    /// The frame that is on the map.
    private(set) var frame: HeatMapFrame?
    /// The time-lapse that is ready, and the month of the frame in it.
    private(set) var lapse: HeatMapTimeLapse?
    private(set) var index = 0
    /// Whether the player is stepping.
    private(set) var isPlaying = false
    /// Whether the area or a frame is being made.
    private(set) var isBusy = false
    private(set) var problem: String?
    /// What the player counts in a frame.
    var spanChoice = SpanChoice.cumulative { didSet { if lapse != nil { Task { await show(index) } } } }
    /// Seconds between two frames while playing.
    var pace = 0.7

    private var area: HeatMapArea?
    private var areaKey: String?
    private var player: Task<Void, Never>?

    /// The overlays for the map: the frame, if there is one.
    var overlays: [any MapOverlay] { frame.map { [$0.overlay] } ?? [] }

    /// The month of the frame that is shown.
    var month: TrackMonth? { lapse?.month(at: index) }

    /// Shows the counts of some categories and months added together.
    ///
    /// - Parameters:
    ///   - store: The store.
    ///   - map: The map the activities were matched on.
    ///   - box: The area (the box of the tracks, for example).
    func showAll(store: TrackStore, map: OpenedMap, box: BoundingBox, categories: Set<String>?, measure: HeatMapMeasure) async {
        await work {
            let area = try await self.area(store: store, map: map, box: box)
            self.stop()
            self.lapse = nil
            self.frame = try await area.frame(categories: categories, measure: measure)
        }
    }

    /// Prepares a time-lapse and shows its first frame.
    func prepareTimeLapse(store: TrackStore, map: OpenedMap, box: BoundingBox, categories: Set<String>?, measure: HeatMapMeasure) async {
        await work {
            let area = try await self.area(store: store, map: map, box: box)
            self.stop()
            guard let lapse = try await area.timeLapse(categories: categories, measure: measure) else {
                self.problem = "There are no activities in those categories."
                return
            }
            self.lapse = lapse
            self.index = 0
            self.frame = await lapse.frame(at: 0, span: self.spanChoice.span)
        }
    }

    /// Shows the frame of a month of the time-lapse.
    func show(_ newIndex: Int) async {
        guard let lapse else { return }
        index = min(max(newIndex, 0), lapse.frameCount - 1)
        frame = await lapse.frame(at: index, span: spanChoice.span)
    }

    /// Plays the months from the one that is shown to the last, then stops.
    func play() {
        guard let lapse, player == nil else { return }
        if index >= lapse.frameCount - 1 { index = 0 }
        isPlaying = true
        player = Task {
            while !Task.isCancelled, index < lapse.frameCount - 1 {
                await show(index + 1)
                try? await Task.sleep(for: .seconds(pace))
            }
            isPlaying = false
            player = nil
        }
    }

    /// Stops the player; the frame stays.
    func stop() {
        player?.cancel()
        player = nil
        isPlaying = false
    }

    /// Takes the heat map off the map.
    func hide() {
        stop()
        frame = nil
        lapse = nil
    }

    private func area(store: TrackStore, map: OpenedMap, box: BoundingBox) async throws -> HeatMapArea {
        let key = "\(map.id)|\(box.south),\(box.west),\(box.north),\(box.east)"
        if let area, areaKey == key { return area }
        let made = try await HeatMapArea.make(store: store, source: map.source, box: box)
        area = made
        areaKey = key
        return made
    }

    private func work(_ body: @escaping () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        problem = nil
        defer { isBusy = false }
        do { try await body() } catch { problem = error.localizedDescription }
    }
}
