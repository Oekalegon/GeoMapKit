import Foundation
import TrackMatching

/// What the store makes of a leg before it keeps it: a range in whole buckets, and the time profile.
struct StoredLeg: Equatable {
    /// The range in metres, rounded to a bucket, from less than to.
    var fromMetre: Int
    var toMetre: Int
    var leg: TrackLeg

    /// The numbers of the buckets that the leg covers.
    var buckets: Range<Int> { (fromMetre / 10)..<(toMetre / 10) }

    /// Rounds the range of a leg to 10 m; `nil` when it rounds to nothing (a leg of under about 10 m is noise).
    init?(_ leg: TrackLeg) {
        func rounded(_ metre: Double) -> Int { Int((metre / BucketCount.length).rounded()) * Int(BucketCount.length) }
        guard leg.lowerMetre.isFinite, leg.upperMetre.isFinite, leg.lowerMetre >= 0 else { return nil }
        let from = rounded(leg.lowerMetre), to = rounded(leg.upperMetre)
        guard to > from else { return nil }
        fromMetre = from
        toMetre = to
        self.leg = leg
    }

    /// The seconds from the start of the leg to the place 25 m, 50 m and so on along it in the direction of travel (the first time it was
    /// that far), as 32-bit floats, interpolated between the samples. The first is 0.
    var profile: Data {
        let samples = leg.samples
        let sign = leg.direction == .forward ? 1.0 : -1.0
        let origin = samples[0].metre
        func along(_ index: Int) -> Double { (samples[index].metre - origin) * sign }
        var seconds: [Float] = [0]
        var index = 1
        var target = 25.0
        let end = along(samples.count - 1)
        let start = samples[0].time
        while target <= max(end, 0), index < samples.count {
            while index < samples.count, along(index) < target { index += 1 }
            guard index < samples.count else { break }
            let before = along(index - 1), after = along(index)
            let fraction = after > before ? (target - before) / (after - before) : 0
            let t0 = samples[index - 1].time.timeIntervalSince(start), t1 = samples[index].time.timeIntervalSince(start)
            seconds.append(Float(t0 + (t1 - t0) * fraction))
            target += 25
        }
        return seconds.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
