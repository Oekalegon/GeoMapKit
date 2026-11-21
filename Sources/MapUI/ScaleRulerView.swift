#if !os(watchOS)
import SwiftUI

/// The scale bar: a line with a tick at each end and the distance over it, on a light card so that it reads on every map colour.
struct ScaleRulerView: View {
    let ruler: ScaleRuler

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(ruler.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.85))
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 5))
                path.addLine(to: CGPoint(x: ruler.length, y: 5))
                path.addLine(to: CGPoint(x: ruler.length, y: 0))
            }
            .stroke(Color.black.opacity(0.85), lineWidth: 1.5)
            .frame(width: ruler.length, height: 6)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Scale")
        .accessibilityValue(ruler.label)
    }
}
#endif
