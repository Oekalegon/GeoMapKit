import SwiftUI
import TrackHeatMap

/// The layers on the map, to switch on and off: the heat map (with its time-lapse) and each track.
///
/// The panel only calls plain methods of the models (`TrackLibrary`, `HeatMapModel`); they start their own tasks.
struct LayersPanel: View {
    @Environment(TrackLibrary.self) private var tracks
    @Environment(ActivityLibrary.self) private var activities
    @Environment(HeatMapModel.self) private var heatMap
    @Environment(MapLibrary.self) private var library
    @State private var problem: String?
    @State private var confirmingShowAll = false

    var body: some View {
        List {
            Section {
                heatMapRows
            } header: { Text("Heat map") }
            Section {
                trackRows
            } header: { Text("Tracks") }
        }
        .task { await activities.refresh() }
        .confirmationDialog("Show \(tracks.items.count) tracks?", isPresented: $confirmingShowAll, titleVisibility: .visible) {
            Button("Show all") { tracks.requestAllVisible(true) }
        } message: {
            Text("Each one is read from its file and drawn.")
        }
    }

    // MARK: Heat map

    @ViewBuilder private var heatMapRows: some View {
        Toggle("Heat map", isOn: Binding(get: { heatMap.hasFrame && heatMap.isVisible }, set: { on in setHeatMap(on) }))
            .disabled(activities.totals.activities == 0 || heatMap.isBusy)
        if activities.totals.activities == 0 { Text("No activities yet").font(.footnote).foregroundStyle(.secondary) }
        if heatMap.isBusy { ProgressView().controlSize(.small) }
        if heatMap.hasFrame {
            Button("Update for this view") { build() }.disabled(heatMap.isBusy)
            if heatMap.isOutOfDate { Text("The database changed").font(.footnote).foregroundStyle(.orange) }
        }
        if let lapse = heatMap.lapse { timeLapse(lapse) }
        if let text = problem ?? heatMap.problem { Text(text).font(.footnote).foregroundStyle(.red) }
    }

    private func timeLapse(_ lapse: HeatMapTimeLapse) -> some View {
        VStack(alignment: .leading) {
            Picker("Frame", selection: Binding(get: { heatMap.spanChoice }, set: { choice in heatMap.spanChoice = choice })) {
                ForEach(HeatMapModel.SpanChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            HStack {
                Button { heatMap.togglePlaying() } label: { Image(systemName: heatMap.isPlaying ? "pause.fill" : "play.fill") }
                    .buttonStyle(.borderless)
                Slider(value: Binding(get: { Double(heatMap.index) }, set: { value in heatMap.seek(to: Int(value.rounded())) }), in: 0...Double(max(lapse.frameCount - 1, 1)), step: 1)
            }
            if let month = heatMap.month { Text(String(format: "%04d-%02d", month.year, month.month)).font(.headline.monospacedDigit()) }
        }
    }

    private func setHeatMap(_ on: Bool) {
        if !on {
            heatMap.setVisible(false)
        } else if heatMap.hasFrame {
            heatMap.setVisible(true)
        } else {
            build()
        }
    }

    /// Makes the heat map of the view again, with what the last one counted; a time-lapse stays one.
    private func build() {
        problem = nil
        guard let store = activities.store, let box = heatMap.viewBox else {
            problem = "The map has not been shown yet."
            return
        }
        do {
            guard let map = try library.openSelected() else {
                problem = "Select a map first."
                return
            }
            heatMap.requestUpdate(store: store, map: map, box: box)
        } catch { problem = error.localizedDescription }
    }

    // MARK: Tracks

    @ViewBuilder private var trackRows: some View {
        if tracks.items.isEmpty {
            Text("No tracks").font(.footnote).foregroundStyle(.secondary)
        } else {
            HStack {
                Button("Show all") {
                    if tracks.items.count > TrackLibrary.confirmShowAllAbove { confirmingShowAll = true } else { tracks.requestAllVisible(true) }
                }
                Button("Hide all") { tracks.requestAllVisible(false) }
            }
            .buttonStyle(.borderless)
            ForEach(tracks.items) { item in
                Toggle(item.name, isOn: Binding(get: { tracks.visible.contains(item.id) }, set: { on in tracks.request(item, visible: on) }))
            }
        }
    }
}
