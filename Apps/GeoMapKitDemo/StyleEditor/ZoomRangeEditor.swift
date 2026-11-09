import MapStyle
import SwiftUI

/// The lowest and the highest zoom at which something is shown.
struct ZoomRangeEditor: View {
    let title: String
    @Binding var range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
            Stepper(value: Binding(get: { range.lowerBound }, set: { range = min($0, range.upperBound)...range.upperBound }), in: 0...24, step: 0.5) {
                Text("From zoom \(String(format: "%g", range.lowerBound))").font(.subheadline)
            }
            Stepper(value: Binding(get: { range.upperBound }, set: { range = range.lowerBound...max($0, range.lowerBound) }), in: 0...24, step: 0.5) {
                Text("To zoom \(String(format: "%g", range.upperBound))").font(.subheadline)
            }
        }
    }
}
