#if os(macOS)
import MapBuilder
import Regions
import SwiftUI

/// Where regions are chosen and turned into a map in the library (question 63; the Mac only).
///
/// The list is the Geofabrik tree. Choosing a region chooses the whole region. "Get maps" asks the server what the files would cost
/// and shows the plan with the free space; nothing is downloaded until "Start" is pressed. Start downloads the files, builds the
/// blocks and the levels and puts the map in the library. The screen closes on Start and the run goes on in the background, with its
/// progress in the status bar (``BuildStatusBar``). A stopped run continues where it stopped. Nothing here limits the size.
struct RegionPickerScreen: View {
    let build: MapBuildModel
    /// Called when a run is started, so that the screen behind (the library) can close too and leave the map free.
    var onStarted: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    private var model: RegionPickerModel { build.picker }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            TextField("Search regions", text: $model.search)
                .textFieldStyle(.roundedBorder)
                .padding([.horizontal, .top], 12)
            content
            Divider()
            footer.padding(12)
        }
        .frame(minWidth: 520, minHeight: 600)
        .task { await model.load() }
        // A run goes on in the background when this screen closes (the status bar shows it); sizes that are still being asked are not wanted.
        .onDisappear { if !build.isRunning { model.cancelPlan() } }
    }

    @ViewBuilder private var content: some View {
        switch model.list {
        case .idle, .loading:
            ProgressView("Loading the list of regions…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 8) {
                Text(message).foregroundStyle(.red)
                Button("Try again") { Task { await model.load() } }
            }
            .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            List(model.visibleRoots, children: \.outlineChildren) { node in
                Toggle(isOn: Binding(get: { model.isSelected(node.id) }, set: { model.setSelected(node.id, $0) })) {
                    Text(node.region.name)
                }
            }
            .disabled(build.isRunning)
        }
    }

    // MARK: Footer

    @ViewBuilder private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.coveredSelections.isEmpty {
                Text("\(model.coveredSelections.map(\.name).joined(separator: ", ")) is part of a larger region that is selected, and is not downloaded on its own.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if model.plan == .none, model.download == .idle {
                Text("Tick the regions you want, then press Get maps. You see the download size first; nothing is downloaded until you press Start. The map is then built in the background: the progress is in the bar at the bottom of the window.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            planView
            downloadView
            HStack {
                actions
                Spacer()
                Button("Done") { dismiss() }
            }
        }
    }

    /// The buttons for the step the flow is in. Start closes the screen: the run goes on in the background.
    @ViewBuilder private var actions: some View {
        switch model.step {
        case .downloading:
            EmptyView()
        case .confirm(let plan):
            Button("Start: download \(RegionPickerModel.size(plan.bytesToDownload)) and build the map") { build.start(); dismiss(); onStarted() }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            Button("Cancel") { model.cancelPlan() }
        case .allHeld:
            Button("Build the map") { build.start(); dismiss(); onStarted() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            Button("Back") { model.cancelPlan() }
        case .chooseRegions, .askSizes, .planning:
            Button("Get maps") { Task { await model.askSizes() } }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(model.step != .askSizes)
        }
    }

    @ViewBuilder private var planView: some View {
        switch model.plan {
        case .none: EmptyView()
        case .planning: ProgressView("Asking the server for the sizes…").controlSize(.small)
        case .failed(let message): Text(message).foregroundStyle(.red).font(.footnote)
        case .ready(let plan):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(plan.items, id: \.region.id) { item in
                    Text("\(model.displayName(of: item.region))\(model.isNeighbour(item.region) ? " (neighbour, needed at the border)" : ""): \(describe(item))").font(.footnote)
                }
                if !plan.needsDownload { Text("Everything is held already; the map is built from the files you have.").font(.footnote) }
                if plan.hasUnknownSizes { Text("The server gave no size for some files.").font(.footnote).foregroundStyle(.secondary) }
                if let note = model.spaceNote(for: plan) { Text(note).font(.footnote).foregroundStyle(.orange) }
            }
        }
    }

    @ViewBuilder private var downloadView: some View {
        switch model.download {
        case .idle: EmptyView()
        case .downloading: DownloadProgressList(model: model)
        case .cancelled: Text("Cancelled. What arrived is kept and the download goes on from there.").font(.footnote)
        case .done: Text("Downloaded.").font(.footnote)
        case .failed(let message): Text(message).font(.footnote).foregroundStyle(.red)
        }
    }

    private func describe(_ item: PlanItem) -> String {
        let size = item.size.map(RegionPickerModel.size) ?? "size unknown"
        switch item.action {
        case .useCached: return "held (\(size))"
        case .download: return item.alreadyDownloaded > 0 ? "\(size), \(RegionPickerModel.size(item.alreadyDownloaded)) held from an earlier try" : size
        case .update: return "\(size), an update of the file that is held"
        }
    }
}
#endif
