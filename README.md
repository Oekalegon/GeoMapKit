# GeoMapKit

A Swift mapping kit with its own vector renderer, for iOS, iPadOS, macOS and watchOS, used first for trail running. OpenStreetMap data (PBF) goes in; a lossless, spatially gridded feature store comes out and is drawn by the renderer.

Status: early. The design is in [docs/design/architecture.md](docs/design/architecture.md).

## Scope

- **v1:** map rendering only, on all platforms.
- **v2:** tracks (GPX, route following).
- **v3:** routing.

## Targets

| Target | Role |
|---|---|
| `GeoCore` | Web Mercator maths, tile coordinates, coordinates and bounding boxes |
| `OSMPBF` | PBF reader (nodes, ways, relations) and area cutting |
| `FeatureStore` | Own feature store (placeholder) |
| `MapStyle` | Style model (placeholder) |
| `MapRender` | Renderer (placeholder) |
| `Regions` | Region manifest, downloads, attribution (placeholder) |
| `MapBuilder` | The build pipeline (blocks, levels, open sea), shared by the tool and the apps |
| `Tracks` | GPX files, the `Route` model (distances, projection) and activity tracks; no platform framework, so the Watch can read a route |

All library targets build for iOS, iPadOS, macOS and watchOS 26, in Swift 6 language mode.

## Tools

`Tools/` is a separate package with the `geomapkit` command-line tool, used to measure the reader and the area cutter on real files. It never downloads anything; get a regional file from [Geofabrik](https://download.geofabrik.de) yourself.

```bash
swift run --package-path Tools -c release geomapkit scan region.osm.pbf
swift run --package-path Tools -c release geomapkit cut region.osm.pbf --center 59.9139,10.7522 --radius-km 15
```

`cut` prints the time per pass, peak memory (heap footprint and resident) and what the extract contains. `track info file.gpx` says what a GPX file holds and whether each track is an activity (points with times, in order). `border-scan` checks that the borders between countries survive the build (`geomapkit border-scan region.osm.pbf --bbox S,W,N,E`): it lists the ways of national border relations that are not stored as a border, and exits with 1 if there are any with no reason; run it on an area with land, river and sea borders after changing the border rules. The commands live in the `ToolCommands` library and return reports, so they are tested; the `geomapkit` executable only parses arguments and prints.

## Build and test

```bash
swift build
swift test
```

## Contributing

Git Flow: feature branches come from `develop` and merge into `develop` by pull request. `main` accepts only `release/*` and `hotfix/*`. PRs are reviewed with the `/geomapkit-pr-review` skill.

## Data

Map data is derived from OpenStreetMap, © OpenStreetMap contributors, available under the ODbL.
