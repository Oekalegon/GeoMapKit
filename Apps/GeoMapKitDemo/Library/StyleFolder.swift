import Foundation

/// Where the styles of the user are kept: the `Styles` folder in the app's Documents, or the same folder in the app's iCloud container, so
/// that the Mac, the iPhone and the iPad share them.
struct StyleFolder: Equatable {
    /// Which of the two it is.
    enum Place: Equatable {
        /// The folder in the app's own Documents on this device.
        case local
        /// The folder in the app's iCloud Drive container, which the system syncs between the devices of the user.
        case iCloud
    }

    /// The folder.
    let url: URL
    /// Whether it is in iCloud.
    let place: Place

    /// The folder to use.
    ///
    /// - Parameters:
    ///   - root: The folder of the library on this device; the local styles are in its `Styles`.
    ///   - useICloud: Whether the user wants the styles in iCloud.
    ///   - ubiquityContainer: The app's iCloud container (`FileManager.url(forUbiquityContainerIdentifier:)`), or `nil` when iCloud is off, not
    ///     signed in, or the app has no container (an unsigned build): then the local folder is used, whatever `useICloud` says.
    static func resolve(root: URL, useICloud: Bool, ubiquityContainer: URL?) -> StyleFolder {
        if useICloud, let ubiquityContainer {
            return StyleFolder(url: ubiquityContainer.appendingPathComponent("Documents", isDirectory: true).appendingPathComponent("Styles", isDirectory: true), place: .iCloud)
        }
        return StyleFolder(url: root.appendingPathComponent("Styles", isDirectory: true), place: .local)
    }
}
