import SwiftUI
import TrackHeatMap

/// The layers on the map, to switch on and off: the heat map (with its time-lapse) and each track.
struct LayersPanel: View {
    @Environment(TrackLibrary.self) private var tracks
    @Environment(ActivityLibrary.self) private var activities
    @Environment(HeatMapModel.self) private var heatMap
    @Environment(MapLibrary.self) private var library
    @State private var problem: String?

    var body: some View {
        List {
            Section("Heat map") {
                Toggle("Heat map", isOn: Binding(get: { heatMap.hasFrame && heatMap.isVisible }, set: setHeatMap))
                    .disabled(activities.totals.activities == 0 || heatMap.isBusy)
                if activities.totals.activities == 0 { Text("No activities yet").font(.footnote).foregroundStyle(.secondary) }
                if heatMap.isBusy { ProgressView().controlSize(.small) }
                if heatMap.hasFrame {
                    Button("Update for this view") { build() }.disabled(heatMap.isBusy)
                    if heatMap.isOutOfDate { Text("The database changed").font(.footnote).foregroundStyle(.orange) }
                }
                if let lapse = heatMap.lapse { timeLapse(lapse) }
                if let problem = problem ?? heatMap.problem { Text(problem).font(.footnote).foregroundStyle(.red) }
            }

            Section("Tracks") {
                if tracks.items.isEmpty { Text("No tracks").font(.footnote).foregroundStyle(.secondary) } else {
                    HStack {
                        Button("Show all") { setAll(true) }
                        Button("Hide all") { setAll(false) }
                    }
                    .buttonStyle(.borderless)
                    ForEach(tracks.items) { item in
                        Toggle(item.name, isOn: Binding(get: { tracks.visible.contains(item.id) }, set: { on in Task { await tracks.setVisible(item, on) } }))
                    }
                }
            }
        }
        .navigationTitle("Layers")
        .task { await activities.refresh() }
    }

    private func timeLapse(_ lapse: HeatMapTimeLapse) -> some View {
        VStack(alignment: .leading) {
            Picker("Frame", selection: Binding(get: { heatMap.spanChoice }, set: { heatMap.spanChoice = $0 })) {
                ForEach(HeatMapModel.SpanChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            HStack {
                Button { Task { if heatMap.isPlaying { await heatMap.stop() } else { await heatMap.play() } } } label: {
                    Image(systemName: heatMap.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderless)
                Slider(
                    value: Binding(get: { Double(heatMap.index) }, set: { value in Task { await heatMap.show(Int(value.rounded())) } }),
                    in: 0...Double(max(lapse.frameCount - 1, 1)), step: 1)
            }
            if let month = heatMap.month { Text(String(format: "%04d-%02d", month.year, month.month)).font(.headline.monospacedDigit()) }
        }
    }

    private func setHeatMap(_ on: Bool) {
        if !on { heatMap.setVisible(false); return }
        if heatMap.hasFrame { heatMap.setVisible(true) } else { build() }
    }

    private func setAll(_ on: Bool) {
        for item in tracks.items where tracks.visible.contains(item.id) != on { Task { await tracks.setVisible(item, on) } }
    }

    /// Makes the heat map of the view, with what the last one counted.
    private func build() {
        problem = nil
        guard let store = activities.store, let box = heatMap.viewBox else { problem = "The map has not been shown yet."; return }
        do {
            guard let map = try library.openSelected() else { problem = "Select a map first."; return }
            Task { await heatMap.showAll(store: store, map: map, box: box, categories: heatMap.categories, measure: heatMap.measure) }
        } catch { problem = error.localizedDescription }
    }
}
