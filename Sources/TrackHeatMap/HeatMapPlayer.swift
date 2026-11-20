import Foundation

/// Plays a ``HeatMapTimeLapse``: moves to a month, steps forward at a pace, and hands the frames to the app.
///
/// A frame costs an overlay to make, so asking for months faster than frames can be made (a slider dragged quickly) is
/// **coalesced**: while a frame is being made, a new request only replaces the one that is waiting, and the frames in between are not
/// made. The frames come out of ``updates``, which keeps only the newest one that nobody has taken yet.
///
/// The player has no timer: a task sleeps for the pace between two steps, and nothing runs while it is paused.
public actor HeatMapPlayer {
    /// The frames, in the order they were made; a slow reader gets the newest and misses the ones between.
    public nonisolated let updates: AsyncStream<HeatMapPlayback>

    private let lapse: HeatMapTimeLapse
    private let continuation: AsyncStream<HeatMapPlayback>.Continuation
    private var span: HeatMapTimeLapse.Span
    private var pace: Duration
    private var index = 0
    private var wanted: Int?
    private var building = false
    private var latest: HeatMapPlayback?
    private var playing = false
    /// Tells a step of a player that has been stopped from a newer one.
    private var generation = 0

    /// Creates a player. It makes no frame until it is asked to.
    ///
    /// - Parameters:
    ///   - lapse: The time-lapse.
    ///   - span: Which months a frame counts.
    ///   - pace: The time between two frames while playing.
    public init(lapse: HeatMapTimeLapse, span: HeatMapTimeLapse.Span = .cumulative, pace: Duration = .milliseconds(700)) {
        self.lapse = lapse
        self.span = span
        self.pace = pace
        (updates, continuation) = AsyncStream.makeStream(of: HeatMapPlayback.self, bufferingPolicy: .bufferingNewest(1))
    }

    /// Whether the player is stepping forward.
    public var isPlaying: Bool { playing }

    /// Goes to a month; one outside the range is brought into it.
    public func seek(to newIndex: Int) async {
        wanted = min(max(newIndex, 0), lapse.frameCount - 1)
        index = wanted ?? index
        await build()
    }

    /// Changes which months a frame counts, and makes the frame of the month that is shown again.
    public func setSpan(_ newSpan: HeatMapTimeLapse.Span) async {
        span = newSpan
        wanted = index
        await build()
    }

    /// Steps forward from the month that is shown to the last, then stops. From the last month it begins again at the first.
    public func play(pace newPace: Duration? = nil) async {
        if let newPace { pace = newPace }
        guard !playing else { return }
        playing = true
        generation += 1
        let mine = generation
        if index >= lapse.frameCount - 1 { await seek(to: 0) }
        Task { await self.step(generation: mine) }
    }

    /// Stops stepping; the frame stays.
    public func pause() {
        guard playing else { return }
        playing = false
        generation += 1
        if let latest { publish(HeatMapPlayback(index: latest.index, frame: latest.frame, isPlaying: false)) }
    }

    /// Ends the stream of updates. The player is not used after this.
    public func close() {
        playing = false
        generation += 1
        continuation.finish()
    }

    private func step(generation mine: Int) async {
        while generation == mine, playing, index < lapse.frameCount - 1 {
            try? await Task.sleep(for: pace)
            guard generation == mine, playing else { return }
            await seek(to: index + 1)
        }
        // Only the step that is still the current one says that the end has been reached.
        guard generation == mine, playing else { return }
        playing = false
        if let latest { publish(HeatMapPlayback(index: latest.index, frame: latest.frame, isPlaying: false)) }
    }

    /// Makes the frames that are wanted, one after the other; a request that comes while one is being made replaces the waiting one.
    private func build() async {
        guard !building else { return }
        building = true
        defer { building = false }
        while let target = wanted {
            wanted = nil
            let frame = await lapse.frame(at: target, span: span)
            publish(HeatMapPlayback(index: target, frame: frame, isPlaying: playing))
        }
    }

    private func publish(_ playback: HeatMapPlayback) {
        latest = playback
        continuation.yield(playback)
    }
}
