import GeoCore
import SwiftUI
import TrackImport

/// Puts the tracks of the library into the segment database, and sets their categories singly or in bulk.
///
/// The choices (which category an activity gets, which are not matched, what a bulk change picks) are the package's
/// (`TrackImport`); this screen only asks for them.
struct ActivitiesScreen: View {
    @Environment(ActivityLibrary.self) private var activities
    @Environment(TrackLibrary.self) private var tracks
    @Environment(MapLibrary.self) private var library

    @State private var from = Date(timeIntervalSince1970: 0)
    @State private var until = Date.now
    @State private var limitDates = false
    @State private var placeID: String?
    @State private var category = "orienteering"
    @State private var problem: String?

    /// The tracks that have a box, to pick a place from.
    private var places: [TrackItem] { tracks.items.filter { tracks.summaries[$0.id]?.box != nil } }

    var body: some View {
        Form {
            Section {
                LabeledContent("Activities", value: "\(activities.totals.activities)")
                LabeledContent("Legs along ways", value: "\(activities.totals.legs)")
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
                Button("Set the category") { start(change: change()) }
                    .disabled(activities.isRunning || category.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: { Text("Set a category in bulk") } footer: {
                Text("The activities that are picked are put in the database again in this category. A category called orienteering is kept as it was recorded, with no matching.")
            }
        }
        .navigationTitle("Activities")
        .task { await activities.refresh(); await tracks.loadSummaries() }
    }

    private func reportView(_ report: ImportReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(report.added) added, \(report.replaced) made again, \(report.skipped) skipped\(report.cancelled ? ", stopped" : "")")
            ForEach(Array(report.failures.prefix(5).enumerated()), id: \.offset) { _, failure in
                Text("\(failure.source): \(failure.message)").font(.footnote).foregroundStyle(.red)
            }
            if report.failures.count > 5 { Text("and \(report.failures.count - 5) more").font(.footnote).foregroundStyle(.secondary) }
        }
    }

    private func change() -> CategoryChange {
        let dates: ClosedRange<Date>? = limitDates && from <= until ? from...until : nil
        let box = placeID.flatMap { tracks.summaries[$0]?.box }
        return CategoryChange(
            selection: ActivitySelection(dates: dates, startsIn: box), category: category.trimmingCharacters(in: .whitespaces))
    }

    private func start(change: CategoryChange?) {
        problem = nil
        guard let id = library.selectedMapID, let item = library.maps.first(where: { $0.id == id }) else {
            problem = "Select a map first: its lines are what the tracks are matched to."
            return
        }
        do {
            let map = try library.open(item)
            activities.start(files: tracks.items.map { tracks.url(of: $0) }, map: map, change: change)
        } catch { problem = "The map cannot be opened: \(error.localizedDescription)" }
    }
}
