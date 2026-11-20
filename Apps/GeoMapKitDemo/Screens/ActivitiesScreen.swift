import GeoCore
import SwiftUI
import TrackHeatMap
import TrackImport
import TrackStorage

/// Puts the tracks of the library into the segment database, and sets their categories singly or in bulk.
///
/// The choices (which category an activity gets, which are not matched, what a bulk change picks) are the package's
/// (`TrackImport`); this screen only asks for them.
struct ActivitiesScreen: View {
    @Environment(ActivityLibrary.self) private var activities
    @Environment(TrackLibrary.self) private var tracks
    @Environment(MapLibrary.self) private var library
    @Environment(HeatMapModel.self) private var heatMap

    @State private var from = Date(timeIntervalSince1970: 0)
    @State private var until = Date.now
    @State private var limitDates = false
    @State private var placeID: String?
    @State private var category = "orienteering"
    @State private var problem: String?
    @State private var heatCategories: Set<String> = []
    @State private var heatMeasure = HeatMapMeasure.activities
    /// `view`, `all`, or the id of a track.
    @State private var heatArea = "view"

    /// The tracks that have a box, to pick a place from.
    private var datesAreValid: Bool { !limitDates || from <= until }

    private var places: [TrackItem] { tracks.items.filter { tracks.summaries[$0.id]?.box != nil } }

    var body: some View {
        Form {
            Section {
                LabeledContent("Activities", value: "\(activities.totals.activities)")
                LabeledContent("Legs along ways", value: "\(activities.totals.legs)")
                LabeledContent("Counted pieces of 10 m", value: "\(activities.totals.countedPieces)")
                LabeledContent("Off-track lines", value: "\(activities.totals.offTrackLines)")
                ForEach(activities.totals.categories.sorted { $0.key < $1.key }, id: \.key) { name, count in
                    LabeledContent(name, value: "\(count)")
                }
            } header: { Text("In the database") }

            Section {
                Button("Import all tracks") { start(change: nil) }.disabled(activities.isRunning || tracks.items.isEmpty)
                if let progress = activities.progress {
                    ProgressView(value: Double(progress.finished), total: Double(max(progress.total, 1))) {
                        Text("\(progress.finished) of \(progress.total): \(progress.source)").font(.footnote)
                    }
                }
                if activities.isRunning { Button("Stop", role: .destructive) { activities.cancel() } }
                if let report = activities.report { reportView(report) }
                if let problem = problem ?? activities.problem { Text(problem).font(.footnote).foregroundStyle(.red) }
            } header: { Text("Import") } footer: {
                Text("The map that is selected gives the lines. A name with orienteering words (OL, NK, orienteering…) suggests orienteering, which is not matched to lines. A file that is in the database in the same category is skipped.")
            }

            Section {
                Toggle("Only activities that started between", isOn: $limitDates)
                if limitDates {
                    DatePicker("From", selection: $from, displayedComponents: .date)
                    DatePicker("Until", selection: $until, displayedComponents: .date)
                }
                Picker("Started in the area of", selection: $placeID) {
                    Text("Anywhere").tag(String?.none)
                    ForEach(places) { Text($0.name).tag(Optional($0.id)) }
                }
                TextField("Category", text: $category)
                if !datesAreValid { Text("From is after Until.").font(.footnote).foregroundStyle(.red) }
                Button("Set the category") { start(change: change()) }
                    .disabled(activities.isRunning || category.trimmingCharacters(in: .whitespaces).isEmpty || !datesAreValid)
            } header: { Text("Set a category in bulk") } footer: {
                Text("Only activities that are in the database are changed; files that were not imported are left alone. A category called orienteering is kept as it was recorded, with no matching. Whole days count, in your time zone.")
            }

            heatMapSection
        }
        .navigationTitle("Activities")
        .task { await activities.refresh(); await tracks.loadSummaries() }
        .onChange(of: activities.totals) { _, _ in heatMap.databaseChanged() }
    }

    // MARK: Heat map

    private var heatMapSection: some View {
        Section {
            Picker("Area", selection: $heatArea) {
                Text("Visible map").tag("view")
                Text("All tracks").tag("all")
                ForEach(places) { Text($0.name).tag($0.id) }
            }
            ForEach(activities.totals.categories.keys.sorted(), id: \.self) { name in
                Toggle(name, isOn: Binding(get: { heatCategories.contains(name) }, set: { if $0 { heatCategories.insert(name) } else { heatCategories.remove(name) } }))
            }
            Picker("Count", selection: $heatMeasure) {
                Text("Activities").tag(HeatMapMeasure.activities)
                Text("Passes").tag(HeatMapMeasure.passes)
            }
            HStack {
                Button("Show") { heat { store, map, box, categories in await heatMap.showAll(store: store, map: map, box: box, categories: categories, measure: heatMeasure) } }
                Button("Time-lapse") { heat { store, map, box, categories in await heatMap.prepareTimeLapse(store: store, map: map, box: box, categories: categories, measure: heatMeasure) } }
                Button("Hide", role: .destructive) { heatMap.hide() }.disabled(heatMap.frame == nil)
            }
            .disabled(heatMap.isBusy)
            if heatMap.isBusy { ProgressView().controlSize(.small) }
            if let lapse = heatMap.lapse { timeLapseControls(lapse) }
            if let frame = heatMap.frame {
                Text("\(frame.bucketCount) pieces of 10 m, most used \(frame.maximumCount)\(frame.months.map { " (" + label($0) + ")" } ?? "")")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let frame = heatMap.frame, frame.bucketCount == 0 { emptyExplanation(frame) }
            if heatMap.isOutOfDate { Text("The database changed since this was made: press Show or Time-lapse again.").font(.footnote).foregroundStyle(.orange) }
            if let problem = heatMap.problem { Text(problem).font(.footnote).foregroundStyle(.red) }
        } header: { Text("Heat map") } footer: {
            Text("The counts of the database drawn on the ways of the selected map. The area is fixed when you press Show: the visible map (zoom in to a city or a region; a very large view is refused), all tracks, or the area of one track. The colour of a count is fixed (1, 2–3, 4–9, 10–29, 30 and more), so months can be compared. No category switched on means all.")
        }
    }

    /// Says why a heat map is empty, from what is known: the ways of the area and the counts of the whole database.
    private func emptyExplanation(_ frame: HeatMapFrame) -> some View {
        let total = activities.totals.countedPieces
        let text: String
        if total == 0 {
            text = "The database has no counted pieces at all: the tracks were stored without legs along ways (they did not follow paths of the selected map, or they are of a category that is not matched). Import again with the map that covers them."
        } else if frame.waysInArea == 0 {
            text = "The map has no paths in this area, so nothing can be drawn here. The database has \(total) counted pieces elsewhere."
        } else {
            text = "Nothing was counted on the \(frame.waysInArea) ways of this area, but the database has \(total) counted pieces elsewhere (the part you look at may be where the track left the paths: that is kept as off-track lines, \(activities.totals.offTrackLines) of them, and is not drawn yet). Try the area of the track."
        }
        return Text(text).font(.footnote).foregroundStyle(.orange)
    }

    private func timeLapseControls(_ lapse: HeatMapTimeLapse) -> some View {
        VStack(alignment: .leading) {
            Picker("Frame", selection: Binding(get: { heatMap.spanChoice }, set: { heatMap.spanChoice = $0 })) {
                ForEach(HeatMapModel.SpanChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            HStack {
                Button { Task { if heatMap.isPlaying { await heatMap.stop() } else { await heatMap.play() } } } label: {
                    Image(systemName: heatMap.isPlaying ? "pause.fill" : "play.fill")
                }
                Slider(
                    value: Binding(get: { Double(heatMap.index) }, set: { value in Task { await heatMap.show(Int(value.rounded())) } }),
                    in: 0...Double(max(lapse.frameCount - 1, 1)), step: 1)
            }
            if let month = heatMap.month { Text(String(format: "%04d-%02d", month.year, month.month)).font(.headline.monospacedDigit()) }
        }
    }

    private func label(_ months: ClosedRange<TrackMonth>) -> String {
        func text(_ month: TrackMonth) -> String { String(format: "%04d-%02d", month.year, month.month) }
        return months.lowerBound == months.upperBound ? text(months.lowerBound) : "\(text(months.lowerBound)) to \(text(months.upperBound))"
    }

    private func heat(_ run: @escaping (TrackStore, OpenedMap, BoundingBox, Set<String>?) async -> Void) {
        problem = nil
        guard let id = library.selectedMapID, let item = library.maps.first(where: { $0.id == id }) else {
            problem = "Select a map first: the counts are drawn on its ways."
            return
        }
        guard let store = activities.store else { return }
        var box: BoundingBox
        if heatArea == "view" {
            guard let view = heatMap.viewBox else {
                heatMap.setProblem("The map has not been shown yet.")
                return
            }
            box = view
        } else {
            let boxes = (heatArea == "all" ? tracks.items.map(\.id) : [heatArea]).compactMap { tracks.summaries[$0]?.box }
            guard var union = boxes.first else {
                problem = "No track has a place yet: wait for the tracks to be read."
                return
            }
            for other in boxes.dropFirst() {
                union = BoundingBox(south: min(union.south, other.south), west: min(union.west, other.west), north: max(union.north, other.north), east: max(union.east, other.east))
            }
            box = union
        }
        do {
            let map = try library.open(item)
            let categories: Set<String>? = heatCategories.isEmpty ? nil : heatCategories
            Task { await run(store, map, box, categories) }
        } catch { problem = "The map cannot be opened: \(error.localizedDescription)" }
    }

    private func reportView(_ report: ImportReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(report.added) added, \(report.replaced) made again, \(report.skipped) skipped\(report.cancelled ? ", stopped" : "")")
            ForEach(Array(report.failures.prefix(5).enumerated()), id: \.offset) { _, failure in
                Text("\(failure.source): \(failure.message)").font(.footnote).foregroundStyle(.red)
            }
            if report.failures.count > 5 { Text("and \(report.failures.count - 5) more").font(.footnote).foregroundStyle(.secondary) }
            if !report.notActivities.isEmpty {
                Text("\(report.notActivities.count) tracks or routes without times were not imported.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func change() -> CategoryChange {
        let box = placeID.flatMap { tracks.summaries[$0]?.box }
        let selection = limitDates && datesAreValid ? ActivitySelection(days: from...until, startsIn: box) : ActivitySelection(startsIn: box)
        return CategoryChange(selection: selection, category: category.trimmingCharacters(in: .whitespaces))
    }

    private func start(change: CategoryChange?) {
        problem = nil
        guard let id = library.selectedMapID, let item = library.maps.first(where: { $0.id == id }) else {
            problem = "Select a map first: its lines are what the tracks are matched to."
            return
        }
        do {
            let map = try library.open(item)
            if let change {
                // A file with one activity that started outside the dates cannot be picked: it is not read at all.
                let files = tracks.items.filter { item in
                    guard let summary = tracks.summaries[item.id], summary.activities == 1, let start = summary.startDate, let dates = change.selection.dates
                    else { return true }
                    return dates.contains(start)
                }
                activities.retag(files: files.map { tracks.url(of: $0) }, map: map, change: change)
            } else {
                activities.start(files: tracks.items.map { tracks.url(of: $0) }, map: map)
            }
        } catch { problem = "The map cannot be opened: \(error.localizedDescription)" }
    }
}
