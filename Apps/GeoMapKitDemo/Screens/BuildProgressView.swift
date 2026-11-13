#if os(macOS)
import MapBuilder
import Regions
import SwiftUI

/// The progress of one download, a line and a bar for each file.
struct DownloadProgressList: View {
    let model: RegionPickerModel

    var body: some View {
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
}

/// The details of a map build, in the popover of the status bar: the regions, each stage with its state, the warnings, and the buttons
/// that fit the state (question 63, step 3d).
struct BuildProgressView: View {
    let build: MapBuildModel
    @Environment(MapLibrary.self) private var library
    @State private var confirmsCancel = false

    private var model: RegionPickerModel { build.picker }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(regionsLine).font(.footnote).foregroundStyle(.secondary)
            stages
            result
            HStack {
                buttons
                Spacer()
            }
        }
        .confirmationDialog("Cancel the map build?", isPresented: $confirmsCancel) {
            Button("Cancel the build", role: .destructive) { build.cancel() }
            Button("Keep building", role: .cancel) {}
        } message: {
            Text("What was downloaded and built is kept. Starting again continues from there.")
        }
    }

    private var regionsLine: String {
        let names: [String]
        if case .ready(let plan) = model.plan { names = plan.items.map { model.displayName(of: $0.region) } }
        else { names = model.effectiveRegions.map(\.name) }
        return names.isEmpty ? "" : "Regions: " + names.joined(separator: ", ")
    }

    @ViewBuilder private var buttons: some View {
        switch build.stage {
        case .checking, .downloading, .buildingBlocks, .buildingLevels, .registering:
            Button("Cancel…") { confirmsCancel = true }
        case .done(let mapID, _):
            Button("Show the map") { library.selectedMapID = mapID; build.dismissResult() }.buttonStyle(.borderedProminent)
            Button("Dismiss") { build.dismissResult() }
        case .cancelled, .failed:
            Button("Continue") { build.start() }.buttonStyle(.borderedProminent)
            Button("Dismiss") { build.dismissResult() }
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder private var result: some View {
        switch build.stage {
        case .done(_, let name):
            Text("The map \u{201C}\(name)\u{201D} is in the library.").font(.footnote).bold()
            rebuildNote
        case .cancelled:
            Text("Cancelled. What was downloaded and built is kept; Continue goes on from there.").font(.footnote)
            rebuildNote
        case .failed(let message):
            Text(message).font(.footnote).foregroundStyle(.red).textSelection(.enabled)
            rebuildNote
        default:
            EmptyView()
        }
    }

    /// Said when a rebuild was stopped: Continue builds what is missing, and blocks it did not reach still count as built.
    @ViewBuilder private var rebuildNote: some View {
        if build.rebuildPending {
            Text("The rebuild was not finished: Continue builds only what is missing, so some blocks keep their old content. To build everything again, press Build again in Get maps.")
                .font(.footnote).foregroundStyle(.orange)
        }
    }

    // MARK: Stages

    private var stages: some View {
        VStack(alignment: .leading, spacing: 6) {
            stageRow("Download", state: state(of: .downloading), detail: downloadDetail) {
                if build.stage == .downloading { DownloadProgressList(model: model) }
            }
            stageRow("Blocks", state: state(of: .buildingBlocks), detail: blocksDetail) {
                if build.stage == .buildingBlocks, let progress = build.blocks { ProgressView(value: progress.fraction) }
                else if build.stage == .buildingBlocks { ProgressView().controlSize(.small) }
            }
            stageRow("Levels", state: state(of: .buildingLevels), detail: build.levelBlocksDone > 0 ? "\(build.levelBlocksDone) level blocks" : nil) {
                if build.stage == .buildingLevels { ProgressView().controlSize(.small) }
            }
            stageRow("Library", state: state(of: .registering), detail: nil) { EmptyView() }
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
            text += ", about \(BuildStatusSummary.timeLeft(remaining)) left"
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
}
#endif
