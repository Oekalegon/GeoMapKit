# GeoMapKit: architecture (first draft)

Status: draft from the first design discussion, 2026-11-06. Nothing is built or verified. Background on frameworks, data sets and licences is in `maps-summary.md` (TrainingApp repo, `docs/design/`); those facts come from memory and need checking.

## 1. Goals

- A mapping kit for iOS, iPadOS, macOS and watchOS, used first for trail running (also walking and cycling).
- Combine data from several sources into tiles, render them with our own renderer, and route with our own router.
- Offline first. Small areas (a valley, a city), not whole countries.
- Pure Swift in the core targets so everything builds for watchOS.

### Battery (watchOS first, not a concern on macOS)

A cross-cutting constraint. A trail run can last hours with GPS, heart rate and the display all active, so the map must add as little as possible. Principles:

- **Draw only when something changed.** Redraw on a new position fix, a Crown turn or a screen wake, never on a timer. No continuous animation.
- **Always-on display:** a reduced, static view (route, position, no animation), redrawn at most about once per second, or per the system's cadence.
- **Cache the rendered view** and move it for small position changes; rebuild only when the position leaves the cached area or the zoom changes.
- **Precompute on the phone,** never on the Watch: simplification per zoom, the corridor graph, the feature cells. The Watch only reads.
- **Memory-mapped, read-only data** with no decode-everything step, so wake-ups stay cheap.
- **Reroute on the Watch is rare and bounded:** it runs only when the phone is out of reach and the runner is off route, on the small corridor graph, with an iteration cap.
- **Location updates and sensors belong to the app's workout session,** not to the map; the kit takes positions as input and does not start its own location updates.
- **Measure:** an energy budget per feature (Instruments Energy Log on a real Watch) is part of definition-of-done for the renderer and the follower.

## 2. Decisions so far

| Topic | Decision |
|---|---|
| Renderer | Own renderer. Core Graphics / SwiftUI `Canvas` backend first, behind a `MapRenderer` protocol. A Metal backend on iOS only if profiling shows a need. |
| Router | Own router. One implementation (A*) for phone and Watch. |
| Map data format | **Own feature store, no MVT and no PMTiles.** All map data comes from our own OSM processing; outside tile sources are not a requirement. Parsed OSM features are stored in a compact format of our own, grouped spatially (by z/x/y or a similar grid) so a Watch corridor can still be cut by region and the renderer loads only what is on screen. |
| Planning | On iPhone, iPad or Mac, on a regional graph for a small downloaded area. |
| Watch | Receives the route, a corridor graph and corridor tiles. It follows the route and only reroutes when the phone is out of reach. |
| Rejoin | After leaving the route, reroute to the best nearby route point, not necessarily back to the exit point (section 6). |
| Route types (v3) | A to B with via-points, out-and-back, and import of a GPX track with map-matching to the graph. No loop generation in v1, but `Router` stays usable by a future loop generator. |
| Activities (v3, routing) | Running and walking (one profile family). Cycling is not in v1, but its edge attributes (one-way, `bicycle` access, `mtb:scale`) are stored in the graph from the start so graphs need no rebuild later. |
| Waypoints | Waypoints carry a `required` flag. A rejoin cannot skip past the next unreached required waypoint. Via-points placed while planning are required by default; optional points of interest are not. |
| Pipeline | Graph building happens **on device**, in Swift, in the package (OSM data for a user-chosen area in, routing graph out). Pre-built server files are not the v1 path. |
| OSM input | OSM data comes as **PBF** (`.osm.pbf`) from the start, read by a Swift PBF reader in the package (`OSMPBF` target). Overpass is not used. The reader sits behind an `OSMDataSource` protocol so the origin of the bytes (bundled file, download, our own host) can change. |
| PBF sourcing | Phase 1: a **test Mac app** that uses the package and downloads full regional PBF files (for example from Geofabrik), cuts the chosen area and builds graph and map data. Phase 2: smaller area PBFs hosted on a server of ours, downloaded by the apps. The area-cutting code lives in the package, so the same code later produces the hosted files. |
| Elevation (v1) | No DEM in v1. The cost model uses tags only (surface, `sac_scale`, road class). The graph format reserves optional ascent/descent fields so a DEM step can be added later without a format break. The Watch barometer remains the source for recorded elevation. |
| Distribution | The kit will be distributed at some point, so licence, attribution and data-source terms are release gates (section 9). |
| Release plan (provisional) | **v1 is map rendering only, on all platforms.** v1: PBF reader, area cutting, lossless feature store, style and labels, the renderer on iOS, iPadOS, macOS and watchOS, a map view with pan and zoom, and delivery of a map region to the Watch (a region cut on the phone or Mac, with no track involved). **Not in v1:** tracks, GPX, route following, track-based corridors and routing. **v2:** tracks (GPX import, a `Route` model, overlay, `RouteFollower`, corridor cut from a track). **v3:** routing (graph builder, router and cost model, route planning, map-matching, rejoin rerouting). The track and routing decisions in this document are the design for those later steps. |
| Off-trail (v2, provisional) | A track created beforehand (for example on the Mac) may go off-trail, and the app must follow it. Orienteering itself is not a use case: routing and tracks are not allowed in competition, so there is no orienteering mode, no ordered controls and no punching. Nothing in v1 may assume that a route lies on paths. A route is an ordered polyline with waypoints, and each leg can be a free leg (straight or free-form, not on any path) or, in v2, a leg on the path network. `RouteFollower` works on any polyline without a graph. Off-route detection on a free leg uses the same rules as on any track. The Watch corridor stays a ribbon around the track. Terrain-cost routing across land cover is not planned (question 41). |
| Cost model (v3) | A `CostProfile` is a table of weights (data, not code), chosen by user preference. Presets: trail running, road running, walking. Adjusted by a few user settings: road avoidance, surface preference and a maximum difficulty (`sac_scale` limit). `mountain_hiking` is acceptable when the user allows it; the limit is a user setting, not a fixed exclusion. Default limit: up to `mountain_hiking` (to confirm). Missing tags default to a mid value, never to the easiest. A full per-surface weight editor is deferred; the data-table design allows it later without a router change. The A* heuristic is computed from the fastest speed of the profile in use, so it stays admissible. |
| Platforms | Minimum version 26 on all platforms: iOS, iPadOS, macOS and watchOS. No availability checks for older systems. |
| Language | Swift 6 language mode with strict concurrency from the start. Value types and `Sendable` by default; explicit isolation (actors) for caches and file readers. |
| Overlays (v2) | A generic `MapOverlay` protocol (points, lines, polygons with a style). Only GPX tracks in v1 (the planned route and the current track). The kit knows nothing about Strava or HealthKit. |

## 3. Modules

| Module | Role | Platforms |
|---|---|---|
| `GeoCore` | Web Mercator maths, tile coordinates, bounding boxes, geometry | all |
| `FeatureStore` | Own compact, spatially grouped feature format: writer, memory-mapped reader, `FeatureSource` protocol, cache | all |
| `MapStyle` | Style model with zoom-dependent values | all |
| `MapRender` | `MapRenderer` protocol, Canvas / Core Graphics backend, optional Metal backend | all |
| `Routing` | `Graph` (CSR layout), `Router` (A*), `CostProfile` | all |
| `Corridor` | Cuts a corridor graph and tile set out of a graph and a route polyline | iOS, macOS |
| `RouteFollower` | Progress along the route, snapping, off-route detection, rejoin | all |
| `Regions` | Manifest per region, downloads, attribution | all |
| `OSMPBF` | PBF reader, area cutting, `OSMDataSource` protocol; feeds the feature store and graph builders | all |
| Tools (`Tools/`, Swift command-line) | Build graph and feature store from a PBF; produce hosted area files in phase 2 | Mac or server |

No HealthKit or training logic in the kit, so it stays reusable.

## 4. Data products

From the same OSM source (plus DEM and land cover) the pipeline makes two products:

1. **Render features:** our own feature store, spatially grouped, with per-zoom simplification baked in. (Contours and hillshade are out of v1 because there is no DEM.)
2. **Routing graph:** a compact binary file. Nodes at junctions, edges with length, surface, `sac_scale`, access and ascent/descent from the DEM. Memory-mapped, fixed-width arrays (CSR adjacency), versioned.

Rendered tiles are generalized and clipped, so they cannot be used for routing.

### Feature store layout (decided)

- **Cells:** the standard z/x/y Web Mercator grid at one fixed storage zoom (z13, decided). The index is a sorted, memory-mapped array of `(x, y) -> offset, length`.
- **Bands:** simplified geometry is baked in per zoom band (starting guess: overview z8 to 11, mid z12 to 14, detail z15 and up). The Watch never simplifies. Every feature has a minimum band, so the reader can skip it without decoding.
- **Geometry:** integer coordinates in OSM's native 1e-7 degree units, relative to the cell origin, delta-coded as varints. This is lossless against the OSM source (a coarser grid would quantize it). Simplified bands are extra copies; the detail band is the original geometry.
- **Clipping:** lines and polygons are clipped at cell edges. Every feature has a stable ID (OSM way or relation ID). Each clipped piece carries the ID, `continuesBefore`/`continuesAfter` flags, and its offset along the original line, so the renderer can join pieces, keep dash patterns continuous, draw one label per feature and hit-test whole features. Polygon edges that lie on a cell border are marked artificial, so they are filled but not stroked.
- **No loss of OSM data on macOS and iOS (decided):** the store keeps the same feature granularity as OSM. Every feature (node, way, relation as modelled) is stored with **all of its tags**. A shared dictionary of keys and values and a per-feature list of dictionary indices keep this compact without losing anything. The builder additionally derives a compact **feature class** plus flags for rendering; the class is derived data and never replaces the tags, and features the classifier does not recognize are kept with class `other`. The renderer and style work on classes; everything else (search, inspection, the graph builder, future styling) can read the raw tags. A shared string table holds names and other values.
- **Two files plus a manifest:** `map` (features) and `graph` (routing), with a shared header, version and bounding box. Map features and graph edges share the OSM way ID.
- **Layer profile:** which classes show at which band is a user setting on macOS and iOS (class to lowest visible band, or hidden), applied when reading, so a change needs no rebuild. The Watch has no setting: the phone applies the profile when it cuts the corridor and drops hidden features from the Watch copy. A profile change reaches the Watch with the next corridor.
- **Watch shows less than iOS (decided):** for the same workout and scale, the Watch map shows only the **essential minimum**: what a runner needs while running (the route, the runner's position and the trail or path they are on, with a few anchors such as junctions, water and major roads where useful). Everything else is left to the iPhone: when the runner is lost or wants detail, they use the phone. The Watch feature set is therefore a smaller, fixed profile applied when the corridor is cut, not the user's iOS layer profile. Exception: if the runner has only the Watch with them (no phone), the Watch may need a richer set (for example more path context for navigating when lost). Open: how the Watch knows it is phone-less (phone not reachable) and whether it then switches to a richer profile, which would require the richer features to be present in the corridor already (see question 37).
- **Relations (decided):** all relation types are stored losslessly, as tags plus an ordered member list with roles (member type, ID and role), whatever the type. In addition, the builder derives **assembled geometry** where it helps drawing: multipolygons are assembled into area features with holes (outer and inner rings joined from member ways), and hiking/running route relations get an optional assembled line for drawing and labelling. Assembled geometry is derived data and never replaces the membership list. Relations spanning several cells are stored once, with the member IDs resolvable across cells.
- **Areas that span cells or the extract (decided):**
  - Clipping happens on the **complete assembled polygon**, never on a partial one. Edges that the clip creates along a cell border are marked artificial; the renderer fills the clipped ring and strokes only real edges. Neighbouring cells hold their own piece of the same area and meet at the border, so the area looks continuous. Draw fills without an anti-aliased outline (or with a tiny overlap) to avoid hairline seams between cells.
  - The area cut (see question 31) **completes relations that touch the box**: all member ways of a touching relation are kept whole with their nodes, so multipolygons can be assembled. Completion has a size limit; relations above it are marked incomplete.
  - An area that still cannot be assembled gets an `incomplete` flag and keeps its membership list. The renderer draws the known outline as a line and does not fill it; it never guesses the inside from an open ring.
- **Watch zoom limits and ultras (proposed numbers):** live view zooms out to about 30 km across and in to about 100 m across, with the basemap drawn inside the corridor only. Ultra marathons (50 to 170 km and longer, 10 to 40 hours) are in scope. For a whole-route overview, which may span 100 km or more, the Watch draws a simplified route line plus waypoints (aid stations, the runner's position, remaining distance) and no basemap features, as a separate mode. This needs no overview band. Ultras make these points matter more: very tight battery over 24 hours or more, long corridors (question 39), phone-less runs (question 37), required waypoints at aid stations and checkpoints, GPX import as a main use case, and routes that cross themselves, which makes progress-along-route tracking essential.
- **Ultra hardware assumption (to verify):** ultra runs are assumed to use an Apple Watch Ultra with the maximum battery-saving workout mode. The specs of the newest model are unconfirmed. The principles stay the same on every Watch. Consequence for the kit: do not assume a position fix every second. In power-saving modes GPS and heart rate are sampled less often, so `RouteFollower` thresholds (off-route distance, hysteresis, rejoin tolerance) depend on the observed fix interval and speed, which are inputs; positions between fixes are interpolated along the route; live snapping reports a confidence and does not jump between passes on loops and self-crossings. Tests must include sparse tracks.
- **Watch zoom range (decided):** on the Watch the user does not zoom out further than tens of kilometres for running, or hundreds of kilometres for cycling. The corridor therefore does not need the overview band for running. Overview geometry stays an iOS/macOS concern. A zoomed-out Watch view shows the route and the corridor ribbon around it, and there is no basemap outside the corridor to draw. Cycling is not a Watch map use case (decided): a Watch is not usable as a map while cycling, and cyclists use an iPhone on a handlebar mount. So there is no cycling corridor strategy or coarser Watch band; the Watch map is for running and walking. Cycling is served by the iPhone (and iPad/Mac), which has the full regional graph and all bands. Cycling edge attributes are still stored in the graph (see Activities).
- **Classes are not a filter at build time:** because nothing is dropped, the earlier idea of core and optional classes chosen when an area is built is superseded (reinstate it only if area size turns out to be a problem). What is shown is decided by the layer profile (iOS/macOS) or the fixed Watch profile (corridor cut), both working on derived classes.

## 5. Corridor (Watch data)

**The track is known beforehand (decided; v2, since v1 has no tracks).** For longer runs, ultras especially, the user has a track before the run: a GPX file, or a track created in an app that uses this package on macOS or iOS. The corridor is therefore cut from that track plus a buffer, before the run, on the phone or Mac; the Watch never decides what to load. The v1 corridor holds map features only (the graph part below is v2). Open: runs without a track (question 42).

When a route is sent to the Watch:

- Take all edges within a buffer of the route polyline (starting guess 300 m to 1 km, configurable), plus the junction nodes they connect.
- Edges that cross the buffer boundary are clipped at the nearest node, and those nodes are marked as boundary nodes.
- The result is a few hundred KB at most and uses the same graph format as the regional graph, so the same router code runs on the Watch.
- Corridor features are cut from the regional feature store by spatial cell. Both files go over WatchConnectivity file transfer with the route.
- Edge attributes must be rich enough for all cost profiles (running, walking, cycling), since the Watch cannot fetch more.

## 6. Off-route handling and rejoin

`RouteFollower` owns progress (distance along the route polyline) and off-route detection. Rejoin is a single multi-target search in `Router`:

1. Candidates are route nodes within a search radius, filtered by progress (see below).
2. Search from the runner outward and stop on any node in the target set.
3. Score each candidate as `cost(runner to rejoin point) + cost(remaining route from that point)`. Rejoining further ahead skips route, so the remaining cost drops and that candidate wins when the detour is cheap. Rejoining behind adds already-run route and is penalized or disallowed.

Who reroutes:

1. Phone reachable: ask the phone (full graph, full cost model).
2. Phone not reachable: run the search on the corridor graph.
3. Outside the corridor: no graph is available. Show a straight-line bearing and distance to the route, and say so in the UI.

A Watch reroute is marked provisional and reconciled when the phone is back.

Behaviour rules:

- Candidates use progress as well as proximity, so loops, self-crossings and out-and-back routes do not snap to the wrong pass.
- Hysteresis: require the off-route distance to exceed a threshold for several seconds, and do not replan again until the runner has moved some distance.
- Stability: stick with a chosen rejoin plan unless the runner clearly deviates from it.
- `RejoinPolicy` holds the tunables: search radius, backward allowance, skip limit, mandatory waypoints.

## 7. Renderer scope

Needed in v1: reading features from the feature store, a style model, line joins and caps, polygon fill with holes, tile cache, overzoom, geometry simplification by zoom and culling off-screen features, labels for places, peaks and a few POIs.

Later: curved labels along paths, rotation and continuous zoom polish, live hillshade, 3D terrain, a Metal backend.

## 8. Build order

1. `GeoCore` and `OSMPBF` (Mercator maths, tile coordinates, PBF reader), testable on the Mac.
2. `FeatureStore` and a Canvas renderer, trail layer only: one cell on the Watch simulator.
3. Pipeline v0: an OSM reader and feature builder in Swift (a command-line target first, then called from the app), run on a small extract, so the Swift code has real data from the start.
4. Style and labels, then the Mac test app with a map view.
5. iOS and watchOS rendering, and region transfer to the Watch (WatchConnectivity). **End of v1.**
6. (v2) Tracks: GPX import, `Route` model, overlay, `RouteFollower`, corridor cut from a track.
7. (v3) Routing: graph builder and format, A* router with a command-line harness that prints routes as GPX, map-matching, corridor graph and rejoin rerouting.
8. (later) Contours and hillshade once a DEM is in scope.

The router can be developed and verified on the Mac with no UI, in parallel with the renderer.

The test Mac app (phase 1 of PBF sourcing) is the first consumer of the package: download a full PBF, cut an area, build, view, route. It is also where measurements for the on-device budget are taken. It is built alongside steps 3 and 4.

## 9. Open questions

**Scope** (questions 1 to 4 settled, see section 2)
1. Resolved: A to B, via-points, out-and-back, GPX import with map-matching. Loops later.
2. Resolved: running and walking; cycling attributes stored only.
3. Resolved: required waypoints. Still open: the UI for marking them.
4. Resolved: GPX overlays only.
22. Map-matching a GPX track to the graph: how to handle gaps in the graph (the track leaves known paths), noisy tracks and tracks that cross themselves? Include a confidence measure and a fallback of keeping the raw line.
23. Which waypoints in an imported GPX become required: the GPX `wpt` elements, or none by default?

**Data and pipeline**
5. Resolved: graph building on device, in Swift. New questions this raises: 24 to 27 below.
6. Resolved: no DEM in v1; ascent/descent fields reserved in the graph format. Later: source per area and smoothing (see `maps-summary.md`).
7. Resolved as a gate: the kit will be distributed. Still open: licence and attribution per data set, and whether ODbL share-alike applies to derived tile and graph files.
24. Resolved: PBF format, sourced in two phases (see section 2): full regional PBFs in a test Mac app first, small hosted area PBFs later. Still open for phase 2: the host, the list of regions or whether areas are cut on request, and the file naming and manifest. Geofabrik is fine for development, but distribution needs our own mirror (check their terms).
31. Area cutting: a bounding-box cut that keeps ways crossing the box edge (with the nodes they need) and keeps relations that touch the box. Resolved: ways are kept whole, and relations that touch the box are completed (all member ways kept whole), up to a size limit (see "Areas that span cells or the extract"). Open: the size limit, and the cost of completing very large relations such as national park boundaries. This code is shared by the Mac test app and the later server-side file production.
32. Test Mac app scope: which functions does it need beyond downloading and cutting (a map view, route planning, a graph inspector, timing and memory figures)? It should double as the measurement tool for questions 26 and 29.
28. PBF reader scope: nodes, ways and relations are needed (relations for hiking routes). Dense-node decoding, zlib decompression and the two-pass structure (first collect way node IDs, then resolve coordinates) are all required. Which compression library on watchOS-compatible platforms (Apple's Compression framework vs. our own inflate)? Does the reader stream, so memory stays bounded?
29. Node index for resolving way geometry: a compact on-disk or in-memory map from node ID to coordinates. At what area size does this exceed the memory budget (question 26), and do we use a sorted-array index with binary search or a hash map?
30. Update flow: when OSM data changes, how does the user refresh a built area (re-download the PBF, or apply OSM change files)? v1 can just rebuild.
25. Resolved: own feature store, no MVT/PMTiles (section 2). Layout decided (see "Feature store layout"). Still open: 33 to 36 below.
33. Derived class list for v1 with default minimum bands. Granularity is no longer a question for iOS/macOS (lossless, see "Feature store layout"); the list now only drives styling, default visibility and the Watch profile. Decided: no OSM metadata (version, timestamp, changeset, user) for now; the format reserves room to add it later. Resolved: all relation types stored losslessly, multipolygons assembled as derived areas (see "Relations"). Broken or incomplete multipolygons: resolved (complete relations, flag and outline-only fallback). Open: how a relation that crosses cells is addressed (an index from relation ID to the cell that holds it is assumed).
38. Sea and coastline: the sea is not a multipolygon in OSM. Coastlines are open ways with land on the left and water on the right. Either build water areas from the coastline direction (a real task, needed for Norwegian fjords) or draw only the coastline without a water fill. Decide before the first coastal test area.
34. Storage zoom: resolved, z13. Still open: band boundaries (starting guess z8 to 11, z12 to 14, z15 and up; the Watch needs only the mid and detail bands for running, see "Watch zoom range"), to be validated against a Watch screen and file-size measurements. Note a z13 cell is narrower in real distance at Norwegian latitudes (roughly 2 km, not the 5 km at the equator).
35. Resolved: the layer profile is an app-wide setting on iOS and macOS. Still open (minor): whether it syncs between devices (iCloud key-value storage is the obvious candidate), and whether a per-area override is ever wanted.
37. Provisionally decided: always send the richer feature set up front in the corridor, so it is present when the phone is out of reach, **provided it does not impact battery**. The Watch draws only the active profile (essential minimum by default, the richer set when the phone is unreachable), so the extra features cost storage and transfer time, not redraw work. To be verified by measurement; if there is a measurable battery cost, fall back to a per-run user choice ("phone-less run"). Original question: Watch-only runs: the Watch default is the essential minimum (see "Feature store layout"). For runs without the phone, is a richer feature set sent in the corridor up front (costs space and battery), selected by a user choice per run ("phone-less"), or switched on automatically when the phone is unreachable? Sending it up front is the only option that works if the phone is already out of reach.
36. Superseded: building with a chosen class list is no longer needed, since the store is lossless on macOS and iOS. The Watch never builds; it only receives a corridor cut from what the phone has. New question: area size. Without dropping anything, how large is a typical area (buildings and all tags), and is there a size limit for iOS? Measure with the Mac test app; reinstate an optional build-time filter only if needed.
26. Budget for on-device building: area size limit, peak memory, time, and whether it runs in the background (iOS limits) or only while the app is foregrounded.
27. Where do the built graph and tiles live, and how do they sync to other devices (iPad, Mac) and the Watch corridor? Rebuild per device or share the file via iCloud?
8. Trail coverage in OSM for the areas that matter (Norway north, Highlands, Alps); check with `osmium` or `ogr2ogr`.

39. Corridor size for ultras: a 170 km route with a 500 m buffer covers about 170 km² (a rough estimate; measure). What is the maximum route length and corridor size for the Watch, does the buffer narrow for very long routes, what is the Watch storage ceiling, and is the corridor sent in stages (for example the next stretch first) over WatchConnectivity? Measure with the Mac test app on a real 100 km course.

40. Minimum Watch hardware and power modes: which Watch models must work, and how does the kit behave in extended-battery or low-power workout modes (fix rate, background time, screen behaviour)? Does `RouteFollower` run in the workout session's process? Verify against the current watchOS documentation and a real device.

41. Deferred to v2 (tracks): no orienteering mode; tracks may be off-trail and are followed like any track. Track creation is a GPX file or an app using this package on macOS or iOS; which editing operations the `Route` model offers is open.

42. Map regions for the Watch (v1 has no tracks): the Watch receives a region around a chosen location, cut by the phone or Mac before the run (a radius, default a few km, configurable; or a bounding box chosen on the map). On-demand cells from the phone are deferred. Open: the default radius, how the region is chosen when the phone has no fix, how much the Watch can store (several regions?), and what the Watch shows outside the region (nothing, with a notice).

**Routing**
9. Resolved in outline (see "Cost model" in section 2): presets plus a few sliders, `sac_scale` limit as a user setting. Still open: the actual numbers per preset (speed factors per surface and highway class, penalties for barriers, steps and poor trail visibility), to be tuned on real routes; and grade-dependent speed once a DEM exists.
10. Is plain A* fast enough on a small-area graph on iPhone, or do we need ALT or contraction hierarchies? Measure first.
11. Resolved: v1 has no routing, so no turn-by-turn instructions in v1 (see "Release plan"). Revisit with the router in v3.
12. Corridor buffer width: fixed, or scaled by edge density (wider in open terrain, narrower in towns)?
13. Skip policy on rejoin: free skipping, a limit, or mandatory waypoints only?

**Renderer**
14. Label requirements: how much text, which languages, and is curved text along paths in v1?
15. Style authoring: a Swift DSL, a JSON style of our own, or a subset of the MapLibre style spec?
16. Watch rendering budget: target frame rate, always-on display behaviour, and a memory ceiling for decoded tiles.

**Platform and project**
17. Resolved: version 26 minimum on all platforms.
18. Resolved: not needed. PMTiles and MVT are not used.
19. One repo with several Swift package targets and `Tools/` for the pipeline (current assumption). Is a separate repo for the pipeline wanted?
20. Resolved: Swift 6 language mode with strict concurrency.
21. Sync and reconciliation: how does a provisional Watch reroute merge with the phone's plan, and what does the activity record keep?
