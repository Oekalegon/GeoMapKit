#if os(macOS)
import MapBuilder
import SwiftUI

/// The strip at the bottom of a window that shows a map build: the stage, a progress bar and a short detail. A click opens the details
/// (question 63, step 3d). It is not there while no run is going and none has ended.
struct BuildStatusBar: View {
    @Environment(MapBuildHost.self) private var host
    @State private var showsDetails = false

    var body: some View {
        if let build = host.model, build.stage != .idle {
            let summary = build.summary
            Button { showsDetails.toggle() } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon(build.stage)).foregroundStyle(color(build.stage))
                    Text(summary.title).font(.footnote).bold().lineLimit(1)
                    if !summary.hasEnded {
                        if let fraction = summary.fraction { ProgressView(value: fraction).frame(width: 160) }
                        else { ProgressView().controlSize(.small) }
                    }
                    if let detail = summary.detail { Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
                    Spacer()
                    Image(systemName: "chevron.up").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(.bar)
            .popover(isPresented: $showsDetails, arrowEdge: .top) { BuildProgressView(build: build).frame(width: 400).padding(14) }
            .accessibilityLabel("Map build: \(summary.title)")
        }
    }

    private func icon(_ stage: MapBuildModel.Stage) -> String {
        switch stage {
        case .done: "checkmark.circle.fill"
        case .cancelled: "pause.circle"
        case .failed: "exclamationmark.triangle.fill"
        default: "arrow.down.circle"
        }
    }

    private func color(_ stage: MapBuildModel.Stage) -> Color {
        switch stage {
        case .done: .green
        case .failed: .red
        default: .secondary
        }
    }
}
#endif
