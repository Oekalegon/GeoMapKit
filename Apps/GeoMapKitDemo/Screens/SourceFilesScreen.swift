#if os(macOS)
import SwiftUI

/// The downloaded source files of the app: what each takes, which maps were built from it, and deleting them (question 63).
///
/// A built map does not read its source files again, so deleting a file changes no map. While a map is being built the files cannot
/// be deleted.
struct SourceFilesScreen: View {
    let build: MapBuildModel
    let isBusy: Bool
    /// The names of the maps in the library by the name of their folder.
    let mapNames: [String: String]
    @State private var model: SourceFilesModel
    @State private var pending: Pending?
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    /// What the user asked to delete and has to confirm.
    private enum Pending: Identifiable {
        case one(SourceFilesModel.File), unused
        var id: String {
            switch self {
            case .one(let file): file.id
            case .unused: "unused"
            }
        }
    }

    init(build: MapBuildModel, isBusy: Bool, mapNames: [String: String]) {
        self.build = build
        self.isBusy = isBusy
        self.mapNames = mapNames
        _model = State(initialValue: build.makeSourceFilesModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.files.isEmpty {
                Text(model.isLoading ? "Reading the folder…" : "No downloaded files.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.files) { file in row(file) }
            }
            Divider()
            footer.padding(12)
        }
        .frame(minWidth: 560, minHeight: 480)
        .task {
            await build.picker.load()
            await model.reload(mapNames: mapNames)
        }
        .confirmationDialog(title, isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { confirm() }
        } message: { Text(message) }
        .alert("Downloaded files", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK") { problem = nil }
        } message: { Text(problem ?? "") }
    }

    // MARK: Rows

    private func row(_ file: SourceFilesModel.File) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                Text(detail(of: file)).font(.footnote).foregroundStyle(.secondary)
                Text(usage(of: file)).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Text(RegionPickerModel.size(file.bytes)).monospacedDigit()
            Button { pending = .one(file) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).disabled(isBusy)
                .help(isBusy ? "A map is being built; wait for it, or dismiss its result." : "Delete this file")
        }
    }

    private func detail(of file: SourceFilesModel.File) -> String {
        switch file.state {
        case .file(let downloaded, let checked):
            "Downloaded \(downloaded.formatted(date: .abbreviated, time: .omitted)), checked \(checked.formatted(date: .abbreviated, time: .omitted))"
        case .damaged(let reason): "Cannot be used: \(reason). It is downloaded again when a map needs it."
        case .unfinished: "An unfinished download; a new download continues after these bytes."
        }
    }

    private func usage(of file: SourceFilesModel.File) -> String {
        guard case .file = file.state else { return "" }
        return file.usedBy.isEmpty ? "No map of this app was built from it." : "Built into: " + file.usedBy.joined(separator: ", ")
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summary).font(.footnote).foregroundStyle(.secondary)
            HStack {
                Button("Delete unused files…") { pending = .unused }
                    .disabled(isBusy || model.unused.isEmpty)
                    .help("Files that no map of this app was built from, files that cannot be used, and unfinished downloads")
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private var summary: String {
        var text = "\(model.files.count) files, \(RegionPickerModel.size(model.totalBytes))"
        if let free = model.availableBytes { text += "; \(RegionPickerModel.size(free)) free on this Mac" }
        return text + ". A built map does not need its source files; Build again and Add a region download what they need."
    }

    // MARK: Deleting

    private var title: String {
        switch pending {
        case .one(let file): "Delete the file of \(file.name)?"
        case .unused: "Delete \(model.unused.count) files that no map needs?"
        case nil: ""
        }
    }

    private var message: String {
        switch pending {
        case .one(let file):
            let base = "This frees \(RegionPickerModel.size(file.bytes))."
            if case .file = file.state, !file.usedBy.isEmpty {
                return base + " \(file.usedBy.joined(separator: ", ")) was built from it and keeps working; Build again or Add a region downloads the file again."
            }
            return base
        case .unused:
            return "This frees \(RegionPickerModel.size(model.unused.reduce(0) { $0 + $1.bytes })): files no map of this app was built from, files that cannot be used, and unfinished downloads. It cannot be undone."
        case nil: return ""
        }
    }

    private func confirm() {
        guard let pending else { return }
        do {
            switch pending {
            case .one(let file): try model.delete(file, isBusy: isBusy)
            case .unused: try model.deleteUnused(isBusy: isBusy)
            }
        } catch {
            problem = error.localizedDescription
        }
        Task { await model.reload(mapNames: mapNames) }
    }
}
#endif
