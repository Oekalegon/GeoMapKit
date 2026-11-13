# GeoMapKit test apps

An Xcode project with the test apps of GeoMapKit (see question 32 in `docs/design/architecture.md`):

| Target | What it is |
|---|---|
| `GeoMapKitDemo` | iPhone, iPad and Mac: the map of the stores in the library, the library of maps and styles, the position of the user, a cut of a Watch copy of the open map, on the Mac "Get maps…" (choose Geofabrik regions, see the sizes and the free space, download the source files with a Start step; the build to a map comes next), and a style editor (forms for the classes, a JSON editor, a live map, undo, save). The Mac version is the same SwiftUI code (scroll wheel zoom, toolbar buttons). |
| `GeoMapKitDemoWatch` | The Watch app: the maps the iPhone sent (by WatchConnectivity file transfer) and a map of each in the Watch style. The Watch does not ask for areas yet; the phone pushes. |
| `GeoMapKitDemoTests` | Tests of the library and of the region picker (iOS Simulator and Mac). |

## Open and run

```bash
open Apps/GeoMapKitDemo.xcodeproj
```

Choose the scheme `GeoMapKitDemo` and an iPhone simulator, or "My Mac", and run. The simulators and the Mac run without a team. For a device, set
`DEVELOPMENT_TEAM` (and, if you want, `APP_BUNDLE_PREFIX`) in `Apps/Config.xcconfig`.

The project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The generated project is
committed so that it opens at once; after a change in `project.yml` run `xcodegen` in this folder and commit the result. The apps use the package one
level up (`..`), so a change in the kit is in the app at the next build.

## Maps and styles

The app keeps two folders in its Documents, which the Files app and Finder can see:

- `Maps/`: `.gmk` store files (copied in, up to 100 MB), and `.maplink` files that point to a folder of blocks (a `manifest.json` and its block files) or
  to a store file over 100 MB, which stay where they are: a set of blocks can be several gigabytes, and a copy of a big file would take long.
- `Styles/`: style files (`.json`) that the kit can read; the two built-in styles (Standard, Watch) can be copied here from the library to be changed.

Add things in the app (Library > +), by opening a file with the app (Files, AirDrop, Finder), or, in the simulator, by copying into the folder:

```bash
xcrun simctl get_app_container booted org.oekalegon.GeoMapKitDemo data     # the folder of the app
```

`scripts/make-sample.sh` builds a small sample (Liechtenstein, about 4 MB) with the `geomapkit` tool; it downloads 3.5 MB from Geofabrik, so it is
not run by anything else. It needs the `Tools` package, which has to sit in a folder named `GeoMapKit` (a git worktree with another name does not
work). Bigger maps are made with `geomapkit build` or `geomapkit build-region` (see `Tools/`).

## Tests

```bash
xcodebuild test -project Apps/GeoMapKitDemo.xcodeproj -scheme GeoMapKitDemo -destination 'platform=macOS'
xcodebuild test -project Apps/GeoMapKitDemo.xcodeproj -scheme GeoMapKitDemo -destination 'platform=iOS Simulator,name=<any iPhone simulator you have>'
```

CI (`.github/workflows/swift.yml`, job `apps`) checks that the committed project is what `project.yml` generates, runs the library tests on the Mac and builds the
iOS and Watch apps for the simulators.

## Styles in iCloud

The styles (not the maps) can be kept in the app's iCloud Drive folder, so a style saved on the Mac is on the iPhone and iPad too (question 56). It needs a team and the iCloud entitlements, which an unsigned build cannot carry, so it is off until you set it up:

1. In `Config.xcconfig` set `DEVELOPMENT_TEAM`, and switch `APP_ENTITLEMENTS_MAC` and `APP_ENTITLEMENTS_IOS` to the two `-iCloud` files (the lines are there, commented).
2. In the Apple developer account, the app ids `org.oekalegon.GeoMapKitDemo` need the iCloud capability with the container `iCloud.org.oekalegon.GeoMapKitDemo` (Xcode does it under Signing & Capabilities). With another `APP_BUNDLE_PREFIX` change the container name in the two entitlements files and in `project.yml`, then run `xcodegen`.
3. Run on the Mac and on an iPhone signed in with the same Apple ID. The library shows a section "iCloud" with a switch and what is happening ("Syncing…", "up to date", or why iCloud is not available).
4. The first time, the styles of the device are copied into iCloud; nothing is overwritten or removed. When two devices change one style, the newest wins and the other is saved as `name (conflict date).json` beside it.

Without this setup the app keeps the styles on the device, as before, and the library says so.

