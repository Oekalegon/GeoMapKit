import SwiftUI

/// The maps on the Watch, newest first. A map is opened with a tap and removed with a swipe.
struct WatchMapList: View {
    @Environment(WatchLink.self) private var link
    @State private var maps: [WatchMapEntry] = []
    @State private var path: [String] = []
    @State private var problem: String?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if maps.isEmpty {
                    Text("No map yet. On the iPhone, open the map, choose Cut for the Watch, and send it.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(maps) { map in
                    NavigationLink(value: map.id) {
                        VStack(alignment: .leading) {
                            Text(map.name)
                            Text(ByteCountFormatter.string(fromByteCount: map.bytes, countStyle: .file))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { try? link.store.delete(maps[index]) }
                    reload()
                }
                if let message = problem ?? link.lastProblem {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
            }
            .navigationTitle("Maps")
            .navigationDestination(for: String.self) { id in
                if let map = maps.first(where: { $0.id == id }) {
                    WatchMapScreen(map: map)
                } else {
                    Text("This map is gone.")
                }
            }
        }
        .onAppear { reload() }
        .onChange(of: link.received) { _, _ in reload() }
    }

    private func reload() {
        maps = link.store.list()
    }
}
