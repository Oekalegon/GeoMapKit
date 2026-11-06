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
| `GeoCore` | Web Mercator maths, tile coordinates, geometry (has code) |
| `OSMPBF` | PBF reader, area cutting (placeholder) |
| `FeatureStore` | Own feature store (placeholder) |
| `MapStyle` | Style model (placeholder) |
| `MapRender` | Renderer (placeholder) |
| `Regions` | Region manifest, downloads, attribution (placeholder) |

All library targets build for iOS, iPadOS, macOS and watchOS 26, in Swift 6 language mode.

## Build and test

```bash
swift build
swift test
```

## Contributing

Git Flow: feature branches come from `develop` and merge into `develop` by pull request. `main` accepts only `release/*` and `hotfix/*`. PRs are reviewed with the `/geomapkit-pr-review` skill.

## Data

Map data is derived from OpenStreetMap, © OpenStreetMap contributors, available under the ODbL.
