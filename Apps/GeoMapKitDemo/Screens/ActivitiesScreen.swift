import GeoCore
import SwiftUI
import TrackHeatMap
import TrackImport
import TrackStorage

/// Puts the tracks of the library into the segment database, sets categories in bulk, and makes the heat map.
///
/// The choices (which category an activity gets, what a bulk change picks, why a picture is empty) are the package's
/// (`TrackImport`, `TrackHeatMap`); this screen only asks for them. The heat map is switched on and off, and played, in the layers panel
/// beside the map.
struct ActivitiesScreen: View {
    @Environment(ActivityLibrary.self) private var activities
    @Environment(TrackLibrary.self) private var tracks
    @Environment(MapLibrary.self) private var library
    @Environment(HeatMapModel.self) private var heatMap

    @State private var from = Date(timeIntervalSince1970: 0)
    @State private var until = Date.now
    @State private var limitDates = false
    @State private var placeID: String?
    @State private var category = ""
    @State private var problem: String?
    @State private var heatCategories: Set<String> = []
    @State private var heatMeasure = HeatMapMeasure.activities
    /// `view`, `all`, or the id of a track.
    @State private var heatArea = "view"

    private var datesAreValid: Bool { !limitDates || from <= until }

    private var places: [TrackItem] { tracks.items.filter { tracks.summaries[$0.id]?.box != nil } }

    var body: some View {
        Form {
            Section("In the database") {
                LabeledContent("Activities", value: "\(activities.totals.activities)")
                LabeledContent("Counted pieces of 10 m", value: "\(activities.totals.countedPieces)")
                ForEach(activities.totals.categories.sorted { $0.key < $1.key }, id: \.key) { name, count in
                    LabeledContent(name, value: "\(count)")
                }
            }

            Section("Import") {
                Button("Import all tracks") { importAll() }.disabled(activities.isRunning || tracks.items.isEmpty)
                if let progress = activities.progress {
                    ProgressView(value: Double(progress.finished), total: Double(max(progress.total, 1))) {
                        Text("\(progress.finished) of \(progress.total)").font(.footnote)
                    }
                }
                if activities.isRunning { Button("Stop", role: .destructive) { activities.cancel() } }
                if let report = activities.report { reportView(report) }
                if let problem = problem ?? activities.problem { Text(problem).font(.footnote).foregroundStyle(.red) }
            }

            Section {
                DisclosureGroup("Set the category in bulk") {
                    Toggle("Only between dates", isOn: $limitDates)
                    if limitDates {
                        DatePicker("From", selection: $from, displayedComponents: .date)
                        DatePicker("Until", selection: $until, displayedComponents: .date)
                        if !datesAreValid { Text("From is after Until").font(.footnote).foregroundStyle(.red) }
                    }
                    Picker("Started in", selection: $placeID) {
                        Text("Anywhere").tag(String?.none)
                        ForEach(places) { Text($0.name).tag(Optional($0.id)) }
                    }
                    TextField("Category", text: $category)
                    Button("Apply") { retag() }
                        .disabled(activities.isRunning || category.trimmingCharacters(in: .whitespaces).isEmpty || !datesAreValid)
                }
            }

            heatMapSection
        }
        .navigationTitle("Activities")
        .task { await activities.refresh(); await tracks.loadSummaries() }
        .onChange(of: activities.totals) { _, _ in heatMap.databaseChanged() }
    }

    // MARK: Heat map

    private var heatMapSection: some View {
        Section("Heat map") {
            Picker("Area", selection: $heatArea) {
                Text("Visible map").tag("view")
                Text("All tracks").tag("all")
                ForEach(places) { Text($0.name).tag($0.id) }
            }
            if activities.totals.categories.count > 1 {
                ForEach(activities.totals.categories.keys.sorted(), id: \.self) { name in
                    Toggle(name, isOn: Binding(get: { heatCategories.contains(name) }, set: { if $0 { heatCategories.insert(name) } else { heatCategories.remove(name) } }))
                }
            }
            Picker("Count", selection: $heatMeasure) {
                Text("Activities").tag(HeatMapMeasure.activities)
                Text("Passes").tag(HeatMapMeasure.passes)
            }
            HStack {
                Button("Show") { heat(lapse: false) }
                Button("Time-lapse") { heat(lapse: true) }
            }
            .disabled(heatMap.isBusy)
            if heatMap.isBusy { ProgressView().controlSize(.small) }
            if let frame = heatMap.frame {
                Text("\(frame.bucketCount) pieces, most used \(frame.maximumCount)\(frame.months.map { " (" + label($0) + ")" } ?? "")")
                    .font(.footnote).foregroundStyle(.secondary)
                emptyExplanation(frame)
            }
            if let problem = heatMap.problem { Text(problem).font(.footnote).foregroundStyle(.red) }
        }
    }

    /// Says why a heat map is empty; the reason is the package's (`HeatMapFrame.emptiness`), this only puts it in words.
    @ViewBuilder private func emptyExplanation(_ frame: HeatMapFrame) -> some View {
        let total = activities.totals.countedPieces
        if let reason = frame.emptiness(databaseCountedPieces: total) {
            let text: String = switch reason {
            case .databaseHasNoCounts: "No counted pieces in the database. See the import report."
            case .noWaysInArea: "The map has no paths here. \(total) pieces are elsewhere."
            case .nothingInFilter: "Nothing in these months or categories."
            case .countsElsewhere: "Nothing here. \(total) pieces are elsewhere: try the area of the track."
            }
            Text(text).font(.footnote).foregroundStyle(.orange)
        }
    }

    private func label(_ months: ClosedRange<TrackMonth>) -> String {
        func text(_ month: TrackMonth) -> String { String(format: "%04d-%02d", month.year, month.month) }
        return months.lowerBound == months.upperBound ? text(months.lowerBound) : "\(text(months.lowerBound)) to \(text(months.upperBound))"
    }

    private func reportView(_ report: ImportReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(report.added) added, \(report.replaced) made again, \(report.skipped) skipped\(report.cancelled ? ", stopped" : "")")
            ForEach(Array(report.failures.prefix(5).enumerated()), id: \.offset) { _, failure in
                Text("\(failure.source): \(failure.message)").font(.footnote).foregroundStyle(.red)
            }
            if report.failures.count > 5 { Text("and \(report.failures.count - 5) more").font(.footnote).foregroundStyle(.secondary) }
            if !report.notActivities.isEmpty {
                Text("\(report.notActivities.count) without times, not imported").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Actions

    private func importAll() {
        problem = nil
        do {
            guard let map = try library.openSelected() else { problem = "Select a map first."; return }
            activities.start(files: tracks.items.map { tracks.url(of: $0) }, map: map)
        } catch { problem = "The map cannot be opened: \(error.localizedDescription)" }
    }

    private func retag() {
        problem = nil
        let box = placeID.flatMap { tracks.summaries[$0]?.box }
        let selection = limitDates && datesAreValid ? ActivitySelection(days: from...until, startsIn: box) : ActivitySelection(startsIn: box)
        let change = CategoryChange(selection: selection, category: category.trimmingCharacters(in: .whitespaces))
        do {
            guard let map = try library.openSelected() else { problem = "Select a map first."; return }
            // A file with one activity that started outside the dates cannot be picked: it is not read at all.
            let files = tracks.items.filter { item in
                guard let summary = tracks.summaries[item.id], summary.activities == 1, let start = summary.startDate, let dates = selection.dates else { return true }
                return dates.contains(start)
            }
            activities.retag(files: files.map { tracks.url(of: $0) }, map: map, change: change)
        } catch { problem = "The map cannot be opened: \(error.localizedDescription)" }
    }

    private func heat(lapse: Bool) {
        problem = nil
        guard let store = activities.store else { return }
        var box: BoundingBox
        if heatArea == "view" {
            guard let view = heatMap.viewBox else { heatMap.setProblem("The map has not been shown yet."); return }
            box = view
        } else {
            let boxes = (heatArea == "all" ? tracks.items.map(\.id) : [heatArea]).compactMap { tracks.summaries[$0]?.box }
            guard var union = boxes.first else { problem = "No track has a place yet."; return }
            for other in boxes.dropFirst() {
                union = BoundingBox(south: min(union.south, other.south), west: min(union.west, other.west), north: max(union.north, other.north), east: max(union.east, other.east))
            }
            box = union
        }
        do {
            guard let map = try library.openSelected() else { problem = "Select a map first."; return }
            let categories: Set<String>? = heatCategories.isEmpty ? nil : heatCategories
            let measure = heatMeasure
            Task {
                if lapse {
                    await heatMap.prepareTimeLapse(store: store, map: map, box: box, categories: categories, measure: measure)
                } else {
                    await heatMap.showAll(store: store, map: map, box: box, categories: categories, measure: measure)
                }
            }
        } catch { problem = "The map cannot be opened: \(error.localizedDescription)" }
    }
}
