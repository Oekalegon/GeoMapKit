import FeatureStore
import Foundation
import GeoCore
import MapRender
import Observation
import TrackHeatMap
import TrackStorage

/// The heat map on the map, and its time-lapse: what the screen shows.
///
/// What a heat map is (the counts on the ways, the colour scale, the months and their running totals) and how a time-lapse is played
/// (coalescing, pace, pause) are the package's (`TrackHeatMap`: `HeatMapArea`, `HeatMapTimeLapse`, `HeatMapPlayer`). This class holds the
/// choices, the frame that is on the map and the view that the map is showing, and passes the player's frames on to the screen.
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
    /// The database changed after what is on the map was made.
    private(set) var isOutOfDate = false
    /// What the player counts in a frame.
    var spanChoice = SpanChoice.cumulative {
        didSet { if let player { Task { await player.setSpan(spanChoice.span) } } }
    }
    /// The view that the map shows now, kept by the map screen: the default area of a heat map.
    var viewport: MapViewport?

    private var area: HeatMapArea?
    private var areaKey: String?
    private var player: HeatMapPlayer?
    private var listener: Task<Void, Never>?

    /// The overlays for the map: the frame, if there is one.
    var overlays: [any MapOverlay] { frame.map { [$0.overlay] } ?? [] }

    /// The month of the frame that is shown.
    var month: TrackMonth? { lapse?.month(at: index) }

    /// The box of the view, widened a little, or `nil` before the map has been shown.
    var viewBox: BoundingBox? { viewport.map { HeatMapArea.box(of: $0) } }

    /// Shows the counts of some categories and months added together.
    ///
    /// - Parameters:
    ///   - store: The store.
    ///   - map: The map the activities were matched on.
    ///   - box: The area.
    func showAll(store: TrackStore, map: OpenedMap, box: BoundingBox, categories: Set<String>?, measure: HeatMapMeasure) async {
        await work {
            let area = try await self.area(store: store, map: map, box: box)
            self.endPlayer()
            self.frame = try await area.frame(categories: categories, measure: measure)
        }
    }

    /// Prepares a time-lapse and shows its first frame.
    func prepareTimeLapse(store: TrackStore, map: OpenedMap, box: BoundingBox, categories: Set<String>?, measure: HeatMapMeasure) async {
        await work {
            let area = try await self.area(store: store, map: map, box: box)
            self.endPlayer()
            guard let lapse = try await area.timeLapse(categories: categories, measure: measure) else {
                self.problem = "There are no activities in those categories."
                return
            }
            self.lapse = lapse
            self.index = 0
            let player = HeatMapPlayer(lapse: lapse, span: self.spanChoice.span)
            self.player = player
            self.listener = Task {
                for await playback in player.updates {
                    self.frame = playback.frame
                    self.index = playback.index
                    self.isPlaying = playback.isPlaying
                }
            }
            await player.seek(to: 0)
        }
    }

    /// Goes to the month of the time-lapse; asking again before the frame is made replaces the request.
    func show(_ newIndex: Int) async {
        guard let player else { return }
        await player.seek(to: newIndex)
    }

    /// Plays the months from the one that is shown to the last, then stops.
    func play() async { await player?.play() }

    /// Stops the player; the frame stays.
    func stop() async { await player?.pause() }

    /// Takes the heat map off the map.
    func hide() {
        endPlayer()
        frame = nil
    }

    /// Shows a reason why a heat map could not be made.
    func setProblem(_ text: String) { problem = text }

    /// Says that the database changed, so that what is on the map is out of date.
    func databaseChanged() { if frame != nil { isOutOfDate = true } }

    private func endPlayer() {
        if let player { Task { await player.close() } }
        player = nil
        listener?.cancel()
        listener = nil
        lapse = nil
        isPlaying = false
        isOutOfDate = false
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
