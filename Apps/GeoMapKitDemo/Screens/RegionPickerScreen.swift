#if os(macOS)
import MapBuilder
import Regions
import SwiftUI

/// Where regions are chosen and turned into a map in the library (question 63; the Mac only).
///
/// The list is the Geofabrik tree. Choosing a region chooses the whole region. "Get maps" asks the server what the files would cost
/// and shows the plan with the free space; nothing is downloaded until "Start" is pressed. Start downloads the files, builds the
/// blocks and the levels and puts the map in the library, with progress for each stage and a cancel in every one. A stopped run
/// continues where it stopped. Nothing here limits the size.
struct RegionPickerScreen: View {
    let build: MapBuildModel
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
        // Esc and a click outside do not close the screen while a download or a build runs.
        .interactiveDismissDisabled(build.isRunning)
        .task { await model.load() }
        // A run belongs to this screen: when it goes away the run stops (what was downloaded and built is kept).
        .onDisappear { build.cancel() }
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
            .disabled(build.isRunning || model.download == .downloading)
        }
    }

    // MARK: Footer

    @ViewBuilder private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.coveredSelections.isEmpty {
                Text("\(model.coveredSelections.map(\.name).joined(separator: ", ")) is part of a larger region that is selected, and is not downloaded on its own.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if build.stage == .idle {
                if model.plan == .none, model.download == .idle {
                    Text("Tick the regions you want, then press Get maps. You see the download size first; nothing is downloaded until you press Start.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                planView
                downloadView
            } else {
                buildView
            }
            HStack {
                actions
                Spacer()
                Button("Done") { dismiss() }.disabled(build.isRunning)
            }
        }
    }

    /// The buttons for the step the flow is in.
    @ViewBuilder private var actions: some View {
        switch build.stage {
        case .idle:
            switch model.step {
            case .downloading:
                EmptyView()
            case .confirm(let plan):
                Button("Start: download \(RegionPickerModel.size(plan.bytesToDownload)) and build the map") { build.start() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                Button("Cancel") { model.cancelPlan() }
            case .allHeld:
                Button("Build the map") { build.start() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                Button("Back") { model.cancelPlan() }
            case .chooseRegions, .askSizes, .planning:
                Button("Get maps") { Task { await model.askSizes() } }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(model.step != .askSizes)
            }
        case .checking, .downloading, .buildingBlocks, .buildingLevels, .registering:
            Button("Cancel") { build.cancel() }
        case .done:
            EmptyView()
        case .cancelled, .failed:
            Button("Continue") { build.start() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            Button("Back") { build.dismissResult() }
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
                    Text("\(item.region.name): \(describe(item))").font(.footnote)
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
        case .downloading: downloadProgress
        case .cancelled: Text("Cancelled. What arrived is kept and the download goes on from there.").font(.footnote)
        case .done: Text("Downloaded.").font(.footnote)
        case .failed(let message): Text(message).font(.footnote).foregroundStyle(.red)
        }
    }

    private var downloadProgress: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(model.progress.keys.sorted(), id: \.self) { id in
                if let item = model.progress[id] {
                    if let size = item.size, size > 0 {
                        ProgressView(value: Double(item.received), total: Double(size)) {
                            Text("\(id): \(RegionPickerModel.size(item.received)) of \(RegionPickerModel.size(size))").font(.footnote)
                        }
                    } else {
                        Text("\(id): \(RegionPickerModel.size(item.received))").font(.footnote)
                    }
                }
            }
        }
    }

    // MARK: Build

    /// The stages of a run, each with what it is doing.
    @ViewBuilder private var buildView: some View {
        VStack(alignment: .leading, spacing: 6) {
            stageRow("Download", state: state(of: .downloading), detail: downloadDetail) {
                if build.stage == .downloading { downloadProgress }
            }
            stageRow("Blocks", state: state(of: .buildingBlocks), detail: blocksDetail) {
                if build.stage == .buildingBlocks, let progress = build.blocks { ProgressView(value: progress.fraction) }
                else if build.stage == .buildingBlocks { ProgressView().controlSize(.small) }
            }
            stageRow("Levels", state: state(of: .buildingLevels), detail: build.levelBlocksDone > 0 ? "\(build.levelBlocksDone) level blocks" : nil) {
                if build.stage == .buildingLevels { ProgressView().controlSize(.small) }
            }
            stageRow("Library", state: state(of: .registering), detail: nil) { EmptyView() }
            switch build.stage {
            case .done(_, let name):
                Text("The map \u{201C}\(name)\u{201D} is in the library and open.").font(.footnote).bold()
            case .cancelled:
                Text("Cancelled. What was downloaded and built is kept; Continue goes on from there.").font(.footnote)
            case .failed(let message):
                Text(message).font(.footnote).foregroundStyle(.red)
            default:
                EmptyView()
            }
            ForEach(build.warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(.orange) }
        }
    }

    private enum RowState { case waiting, running, finished, stopped }

    /// The order of the stages, to tell which have been passed.
    private func rank(_ stage: MapBuildModel.Stage) -> Int {
        switch stage {
        case .idle: 0
        case .checking: 1
        case .downloading: 2
        case .buildingBlocks: 3
        case .buildingLevels: 4
        case .registering: 5
        case .done: 6
        case .cancelled, .failed: -1
        }
    }

    private func state(of stage: MapBuildModel.Stage) -> RowState {
        let current = rank(build.stage)
        if current < 0 { return .stopped }
        let mine = rank(stage)
        return current > mine ? .finished : (current == mine ? .running : .waiting)
    }

    private var downloadDetail: String? {
        if build.stage == .checking { return "checking the files" }
        return build.downloadedFiles ? nil : "nothing to download"
    }

    private var blocksDetail: String? {
        guard let progress = build.blocks else { return nil }
        var text = "\(progress.finished) of \(progress.total) blocks"
        if build.stage == .buildingBlocks, let remaining = progress.remaining {
            text += ", about \(Duration.UnitsFormatStyle(allowedUnits: [.hours, .minutes], width: .abbreviated).format(remaining)) left"
        }
        return text
    }

    private func stageRow<Extra: View>(_ title: String, state: RowState, detail: String?, @ViewBuilder extra: () -> Extra) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: symbol(state)).foregroundStyle(state == .finished ? Color.green : Color.secondary)
                Text(title).font(.footnote).bold(state == .running)
                if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
            }
            extra()
        }
    }

    private func symbol(_ state: RowState) -> String {
        switch state {
        case .waiting: "circle"
        case .running: "circle.dotted"
        case .finished: "checkmark.circle.fill"
        case .stopped: "pause.circle"
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
