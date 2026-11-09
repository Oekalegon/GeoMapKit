import SwiftUI

/// The Watch app. In this step it only says what it will do; the map and the transfer from the phone come later.
@main
struct GeoMapKitDemoWatchApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 8) {
                Image(systemName: "map").font(.title)
                Text("GeoMapKit").font(.headline)
                Text("The map arrives from the iPhone.").font(.footnote).multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}
