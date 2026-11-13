#if os(macOS)
import Regions
import SwiftUI

/// Where regions are chosen and their source files downloaded (question 63, step 2; the Mac only).
///
/// The list is the Geofabrik tree. Choosing a region chooses the whole region. "Check size" asks the server what the files would
/// cost and shows the free space; nothing is downloaded until "Download" is pressed, and the download can be cancelled and goes on
/// later. Nothing here limits the size.
struct RegionPickerScreen: View {
    @Bindable var model: RegionPickerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search regions", text: $model.search)
                .textFieldStyle(.roundedBorder)
                .padding([.horizontal, .top], 12)
            content
            Divider()
            footer.padding(12)
        }
        .frame(minWidth: 520, minHeight: 600)
        // Esc and a click outside do not close the screen while a download runs.
        .interactiveDismissDisabled(model.download == .downloading)
        .task { await model.load() }
        // A download belongs to this screen: when it goes away the download stops (what arrived is kept).
        .onDisappear { model.cancelDownload() }
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
            .disabled(model.download == .downloading)
        }
    }

    @ViewBuilder private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.coveredSelections.isEmpty {
                Text("\(model.coveredSelections.map(\.name).joined(separator: ", ")) is part of a larger region that is selected, and is not downloaded on its own.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if model.plan == .none, model.download == .idle {
                Text("Tick the regions you want, then press Get maps. You see the download size first; nothing is downloaded until you press Start.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            planView
            downloadView
            HStack {
                actions
                Spacer()
                Button("Done") { dismiss() }.disabled(model.download == .downloading)
            }
        }
    }

    /// The buttons for the step the flow is in: Get maps (ask the sizes), then Start or Back, and Cancel while downloading.
    @ViewBuilder private var actions: some View {
        if model.download == .downloading {
            Button("Cancel download") { model.cancelDownload() }
        } else if case .ready(let plan) = model.plan {
            if plan.needsDownload {
                Button("Start: download \(RegionPickerModel.size(plan.bytesToDownload))") { model.startDownload() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            Button(plan.needsDownload ? "Cancel" : "Back") { model.cancelPlan() }
        } else {
            Button("Get maps") { Task { await model.makePlan() } }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(model.effectiveRegions.isEmpty || model.plan == .planning)
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
                if !plan.needsDownload { Text("Everything is held already.").font(.footnote) }
                if plan.hasUnknownSizes { Text("The server gave no size for some files.").font(.footnote).foregroundStyle(.secondary) }
                if let note = model.spaceNote(for: plan) { Text(note).font(.footnote).foregroundStyle(.orange) }
            }
        }
    }

    @ViewBuilder private var downloadView: some View {
        switch model.download {
        case .idle: EmptyView()
        case .downloading:
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
        case .cancelled: Text("Cancelled. What arrived is kept and the download goes on from there.").font(.footnote)
        case .done: Text("Downloaded. The files are in the source cache; the build of the maps comes in the next step.").font(.footnote)
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
