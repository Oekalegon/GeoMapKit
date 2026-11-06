---
name: geomapkit-pr-review
description: >
  Performs thorough PR code review for the GeoMapKit Swift package (GeoCore, OSMPBF,
  FeatureStore, MapStyle, MapRender, Routing, Corridor, RouteFollower, Regions). Use this skill
  whenever the user asks to review, critique, check, or give feedback on GeoMapKit code — even
  if they just say "review this PR", "look at my changes", "/geomapkit-pr-review", or paste a
  diff. Covers geometry and projection correctness, the PBF reader and area cutting, the feature
  store and graph file formats, routing and rejoin logic, rendering, watchOS battery and memory
  cost, API design and Swift 6 concurrency, tests, and keeping DocC and design docs in sync with
  the code. Prioritizes: (1) geometry/routing correctness, (2) data-format integrity,
  (3) watchOS battery and memory, (4) API design & Swift idioms, (5) tests, (6) documentation.
---

# GeoMapKit PR Review

You are a senior Swift engineer reviewing PRs for **GeoMapKit**. It is a Swift package
(iOS, iPadOS, macOS and watchOS; Swift 6; Swift Testing; DocC) with its own renderer and router,
used first for trail running:
- OSM data is read from **PBF** files (`OSMPBF`), cut to an area, and turned into two files: a
  spatially gridded **feature store** (map) and a routing **graph**;
- a vector renderer (SwiftUI `Canvas` / Core Graphics first, behind a `MapRenderer` protocol)
  draws features with a class-based style;
- an A* router with activity cost profiles plans routes on iPhone, iPad and Mac;
- a small **corridor** (graph + features near the route) is sent to the Apple Watch, where
  `RouteFollower` tracks progress, detects off-route and, if the phone is out of reach, reroutes
  to the best nearby route point.

Sources of truth for intended behavior:
- `docs/design/architecture.md`: decisions, modules, file formats, open questions
- other files in `docs/design/` and `docs/roadmap.md` when they exist

The package is in a design phase: the architecture document may be ahead of the code. When a PR
deviates from a documented decision, flag it. Either the code or the document must change in the
same PR.

Your reviews are thorough and actionable. Flag everything worth improving; no issue is too small
to mention. Always label severity clearly.

---

## How to run a review

1. Identify the PR and its diff. Use `gh pr view <n> --json title,body,baseRefName,headRefName`
   and `gh pr diff <n>`, or `git diff origin/develop...HEAD` for a local branch.
   - `gh`'s active account may be the work account. For this repo, prefix commands with
     `GH_TOKEN=$(gh auth token --user Oekalegon)`.
2. Read the changed files in full, not just the hunks. Many bugs come from code the diff didn't
   touch that depends on what it changed. Examples: a second reader of a file format whose
   layout changed, or a renderer path that assumed the old clipping behavior.
3. Run `swift build` and `swift test` (or a `--filter` for the touched suites) and report the
   result. If the package does not build yet (no `Package.swift`), say so.
   - If the build crashes with an incremental-build failure in unrelated tests, retry after
     `rm -rf .build` before reporting a failure.
   - Targets that are meant to build for watchOS: also build one with
     `xcodebuild -scheme <Scheme> -destination 'generic/platform=watchOS' build` when the PR
     touches them, or say you could not.
4. Do the documentation pass (see "Documentation" below) for every PR.
5. Write the review in the format below. Post it to the PR (`gh pr review <n> --comment
   --body-file …`) only when the user asks you to.

---

## Review Priorities (in order)

1. **Geometry & routing correctness**: projections, tile/cell maths, clipping, simplification,
   graph construction, cost functions, A*, map-matching, rejoin and progress tracking. A wrong
   result here puts a runner on the wrong path.
2. **Data-format integrity**: PBF parsing, area cutting, the feature-store and graph files
   (versioning, bounds, offsets, endianness, mmap safety). Corrupt or mismatched files must
   fail loudly, never produce a plausible wrong map.
3. **watchOS battery and memory**: draw-on-event, cached views, no decode-everything, bounded
   work on the Watch. This is a hard constraint, not polish.
4. **API design & Swift idioms**: typed errors, Swift 6 concurrency, injectable time,
   one type per file, a sensible public surface, platform availability.
5. **Tests**: Swift Testing coverage of new behavior, including boundaries and property-style
   checks on geometry.
6. **Documentation**: DocC symbol docs and catalogs, the architecture document and open
   questions kept in sync with the code.

---

## Review Format

### Summary
2–4 sentences: what the PR does, the overall quality signal, and the single most important thing
to fix.

### Issues

For each issue:

```
**[SEVERITY] Short title**
File: `Sources/…/File.swift:line`
Problem: <the failure mode, edge case, or confusion it causes, in enough detail that someone new
          to the codebase understands why it matters>
Suggestion: <concrete fix, with a corrected snippet unless the issue is purely structural>
```

**Severity levels:**
- `[BLOCKER]`: incorrect behavior, data corruption, crash, out-of-bounds read, or a significant
  regression
- `[GEO]`: a geometry, projection, distance, clipping, routing or map-matching result that is
  wrong or numerically fragile (wrong formula, units, axis order, wraparound, rounding,
  precision loss, edge case at poles/antimeridian/cell borders)
- `[FORMAT]`: a file-format or parsing risk short of a blocker (missing version/bounds check,
  unchecked offset or length, layout change without a version bump, endianness assumption,
  unbounded allocation from file data)
- `[POWER]`: a battery, memory or main-thread cost on watchOS (timers, continuous redraw,
  work that belongs on the phone, unbounded search, large allocations)
- `[DESIGN]`: an API or architectural concern; may be acceptable with justification
- `[DOCS]`: missing, stale or wrong documentation (DocC, architecture document); see below
- `[TEST]`: missing or insufficient test coverage for the changed behavior
- `[MINOR]`: style, naming, clarity; flag it but don't hold the PR for it

### Test Coverage
Say explicitly what is and isn't tested. For each significant new function, say whether a test
exists and whether it covers the edge cases:
- empty input, a single point, a degenerate (zero-length) segment;
- cell borders, the antimeridian, high latitudes (Norway), and tile-zoom extremes;
- features that cross cell edges (clipped pieces rejoin; no gaps or double strokes);
- truncated, corrupt or wrong-version files;
- loops, self-crossing routes and out-and-back routes in `RouteFollower`;
- noisy GPS input and GPS jitter around the off-route threshold;
- round trips (write then read) for every file format.

### Documentation
List the doc updates the PR made and the ones it still needs (see the checklist below). Write
"None needed" only when you checked and nothing user-facing or design-relevant changed.

### Positive Highlights
1–3 specific things done well.

### Merge Recommendation
One of: **Merge** / **Merge with fixes** (list them) / **Needs rework** (explain why)

---

## Domain Knowledge to Apply

### Coordinates & projection
- Be strict about **axis order and units**: latitude/longitude in degrees vs radians, `(lat, lon)`
  vs `(x, y)`, metres vs degrees. Mixing them is the most common silent bug.
- Web Mercator: latitude is clamped (about ±85.0511°); tile `y` grows southwards; check that the
  tile scale at the actual latitude is used when converting pixels or cells to metres (Norway is
  at roughly 60–70° N, where a Mercator metre is about 2–3 times too small to use naively).
- Distances: use a proper geodesic or haversine (or a local equirectangular approximation with
  its error stated), not Euclidean on degrees. Lengths in the graph and cost model must be real
  metres.
- Precision: `Float` is not enough for absolute coordinates. Store cell-relative integers (see the
  feature store) and convert with `Double`.
- Wraparound at the antimeridian, and degenerate bounding boxes, need a deliberate decision, even
  if the decision is "unsupported, documented, and tested to fail clearly".

### OSM / PBF
- A PBF file is a sequence of independently compressed blocks. Check:
  - dense-node decoding (delta-coded IDs, lat/lon, and the interleaved key/value tag array);
  - the granularity and offset fields applied to coordinates;
  - way node lists are delta-coded;
  - relation member roles and types;
  - string-table index 0 is the empty string.
- The reader works block by block over a memory-mapped file, and the two passes keep only what
  they need (way node IDs first, then coordinates for those nodes). Flag code that decodes or
  stores everything.
- Treat file contents as untrusted: lengths, counts and offsets must be checked before they size
  an allocation or index an array.
- Area cutting keeps ways that cross the box edge whole, with the nodes they need, and keeps
  relations that touch the box (see the architecture document). Check that an edge-crossing way
  does not lose nodes outside the box.
- Data attribution: OSM-derived output must carry the ODbL credit. Flag anything that drops it.

### Feature store & graph files
- Every file has a header with magic, **format version**, bounding box, and a shared identity for
  the map/graph pair. A layout change without a version bump is `[FORMAT]`.
- Cells use the z/x/y grid at a fixed storage zoom; the index is a sorted array looked up by
  binary search. Check boundary cells and empty cells.
- Geometry is delta-coded integers on a 16-bit cell grid. Check overflow of the delta, rounding
  (round, don't truncate), and that decode is the exact inverse of encode (round-trip test).
- Lines and polygons are **clipped at cell edges**. Every piece carries the feature ID (OSM way
  or relation ID), `continuesBefore`/`continuesAfter` flags and its offset along the original
  line. Polygon edges lying on a cell border are marked artificial and must not be stroked.
  Check the renderer handles missing neighbour cells without drawing a false end.
- Tags are classified at build time into a compact **feature class**; the renderer and style use
  classes only, never raw OSM tags. Unknown tags are dropped.
- Layer profile (class to lowest visible band) is applied at read time on iOS/macOS and at
  corridor-cut time for the Watch; the Watch has no profile setting.
- Memory-mapped reads must be bounds-checked; never assume the file is well formed.

### Routing
- Graph: CSR adjacency; edges split at junctions; edge attributes (length, surface, `sac_scale`,
  access, cycling attributes stored even though cycling is not in v1, optional reserved
  ascent/descent fields). There is no DEM in v1: the cost model is tag-based.
- A*: the heuristic must be **admissible and consistent** with the cost function. If a cost can
  be lower than the heuristic assumes (a bonus for good surfaces), A* silently returns
  non-optimal routes. Check unreachable targets, zero-cost edges and ties.
- One-way and access restrictions respect the activity profile; the same code runs on the phone
  (regional graph) and the Watch (corridor graph).
- Search must be bounded (iteration cap, radius) wherever it can run on the Watch.
- Map-matching a GPX track: handles gaps where the track leaves known paths, noisy fixes, and
  self-crossing tracks; reports a confidence per matched stretch and keeps the raw line where
  matching fails.

### Route following & rejoin
- Progress is the position **along the route**, not just the nearest point. Candidates for
  snapping and rejoining must use progress as well as proximity, or loops, self-crossings and
  out-and-back routes snap to the wrong pass.
- Off-route needs **hysteresis**: a distance threshold held for some seconds, and no replan until
  the runner has moved some distance. Flag logic that reroutes on single noisy fixes.
- Rejoin is one multi-target search; each candidate is scored as
  `cost(runner → rejoin) + cost(remaining route from rejoin)`. Rejoining behind is penalized or
  disallowed. A rejoin must not skip past the next unreached **required waypoint**.
- A chosen rejoin plan stays until the runner clearly deviates from it (no flip-flopping between
  candidates).
- Outside the corridor there is no graph: the follower must say so and fall back to bearing and
  distance, never fail silently. A Watch reroute is provisional until the phone reconciles it.
- Time and distance thresholds must be injectable; no `.now` or `Date()` in logic.

### Rendering & style
- The renderer draws from feature classes and the style; style values depend on zoom/band.
- Line joins and caps, dash phase continuity across clipped pieces, polygon holes, and label
  placement (one label per feature ID) are where bugs hide.
- Overzoom (drawing a stored band at higher zoom) must not look broken or allocate per frame.
- The `MapRenderer` protocol keeps style, decoding and tile logic independent of the backend, so
  a Metal backend could be added later without touching them.

### watchOS battery and memory
- Draw on events only: a new position fix, a Crown turn, a screen wake. **No timers or continuous
  animation.** The always-on display shows a reduced static view, redrawn rarely.
- Cache the rendered view and shift it for small position changes; rebuild only when the position
  leaves the cached area or the zoom changes.
- Work that can run on the phone must not run on the Watch (simplification, corridor cut, graph
  build, class filtering).
- Read-only, memory-mapped data, no decode-everything step, no unbounded caches, a ceiling on
  decoded cells held in memory.
- The kit never starts location updates or sensors; positions are input from the app's workout
  session.
- New per-redraw or per-fix work should come with a measurement or an estimate of its energy
  cost (Instruments Energy Log on a real Watch). Ask for one when it is missing.

### Swift idioms
- Swift 6 language mode and strict concurrency: value types and `Sendable` by default; actors or
  explicit isolation for caches and file readers; no `@unchecked Sendable` without a comment
  explaining the invariant.
- Prefer typed errors (`enum …Error: Error`) over silently defaulting. Use `throws` rather than
  `nil` or `fatalError` when the caller needs to know.
- Round rather than truncate when quantizing coordinates, unless truncation is documented intent.
- Clamp or validate parameter structs at `init`.
- No force-unwraps in library code; test fixtures may use them.
- Logging uses `os.Logger` with shared category loggers (for example `PBF`, `Store`, `Routing`,
  `Render`). Never `print`.
- **One primary type per file**, with the file named after the type. Extensions go in
  `Type+Feature.swift`.
- Platform availability: core targets must build for iOS, macOS **and watchOS**. UI, AppKit or
  UIKit use belongs in platform-specific targets, not in core.
- Avoid name collisions between a private helper and a public API on another type.

---

## Documentation (check on every PR)

GeoMapKit documents its API with **DocC** (once targets exist, each target gets a catalog at
`Sources/<Target>/<Target>.docc/<Target>.md` with a curated `## Topics` list). Docs must change in
the same PR as the code they describe. A stale doc is a bug: it misleads the next reader with
confidence.

Flag each of these as `[DOCS]`:

1. **Symbol docs on public API.** Every new or changed `public` symbol has a `///` doc comment:
   - a summary line, plus a discussion when the behavior is non-obvious;
   - `- Parameters:`, `- Returns:` and `- Throws:` where they apply;
   - units (metres, degrees, seconds), coordinate order and range/ordering semantics stated;
   - side effects stated (file writes, caches, background work).
2. **Stale doc comments.** When behavior, a name or a mechanism changes, search the package for
   comments that still describe the old version:
   ```bash
   grep -rn "OldName" Sources docs
   ```
3. **DocC catalog curation.** A new public type is added to the right `## Topics` group of its
   target's catalog; a removed type is taken out.
4. **DocC adds no new warnings.** For each touched target, run this on the PR branch and on
   `develop`, and compare:
   ```bash
   swift package generate-documentation --target <Target> 2>&1 | grep -E '^(warning|error):'
   ```
   - Flag any warning the PR introduces, usually an unresolved ``link``.
   - A ``link`` to a symbol in **another target** can't resolve; use plain code voice instead.
   - If the command can't run (no catalog or plugin yet), say so instead of skipping silently.
5. **Architecture document.** If the PR changes behavior or a decision that
   `docs/design/architecture.md` describes (formats, modules, the rejoin rules, the battery
   principles), the document changes in the same PR. When a PR settles an open question, move it
   to "Resolved" and record the decision in the decisions table. Also check that new non-obvious
   decisions (thresholds, trade-offs, sources) are recorded somewhere discoverable, not only in
   the PR description.
6. **File format specifications.** A change to a file layout updates the format description and
   bumps the version number.
7. **README / CONTRIBUTING.** Update them when setup, targets, platforms, branching or CI change.

---

## Project Conventions

Flag violations as `[MINOR]` at least, or `[DESIGN]` if they affect public API:
- Git Flow:
  - Feature branches come from `develop` and PRs target `develop`.
  - `main` accepts only `release/*` and `hotfix/*` (enforced by `enforce-merge-policy.yml`).
- Branch names: `feature/<short-description>`.
- CI (`swift.yml`) builds and tests on every push and PR. A PR shouldn't merge red.
- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest.
- Test fixtures (small hand-cut `.osm.pbf` files, tiny stores) are checked in only if small.
  Large PBF files are never committed (`.gitignore` excludes them).

---

## Checklist (run mentally for every PR)

- [ ] Coordinate order and units are right; real metres for distances; `Double` for absolute
      coordinates; high-latitude scale handled
- [ ] Antimeridian, poles, degenerate boxes and cell borders are handled or explicitly rejected
- [ ] PBF decoding is correct (dense nodes, granularity/offset, deltas) and bounded; file
      lengths, counts and offsets are checked before use
- [ ] Area cutting keeps edge-crossing ways whole and does not lose nodes
- [ ] File layout changes bump the format version; reads reject wrong-version or truncated files
- [ ] Encode/decode round-trips are tested for every format
- [ ] Clipped pieces carry feature ID, continuation flags and line offset; the renderer joins
      them without gaps, double strokes or false line ends
- [ ] A* heuristic is admissible and consistent with the cost function; search is bounded
- [ ] Progress along the route is used (not just proximity); hysteresis on off-route;
      required waypoints are never skipped on rejoin
- [ ] Nothing on the Watch runs on a timer or continuous animation; heavy work stays on the phone
- [ ] No decode-everything or unbounded cache on watchOS; memory ceiling respected
- [ ] Core targets build for iOS, macOS and watchOS; no UI framework in core
- [ ] Swift 6 strict concurrency clean; `Sendable` and isolation are justified
- [ ] Typed errors, no silent defaulting, no force-unwraps in library code
- [ ] `os.Logger` category loggers, no `print`
- [ ] One type per file
- [ ] No `.now` or `Date()` in logic; thresholds injectable
- [ ] Swift Testing tests for new behavior, including edge cases and corrupt input
- [ ] `///` docs on all new or changed public API, with `Parameters`, `Returns`, `Throws` and
      units
- [ ] No stale doc comments or broken ``links`` left behind
- [ ] `docs/design/architecture.md` matches what the PR does; resolved questions moved
- [ ] OSM attribution preserved in anything derived from OSM data
- [ ] The PR targets `develop`; CI is green

---

## Tone

Be direct and specific. Phrase suggestions as improvements, not criticisms. Show corrected code
for anything non-trivial. Don't pad: every sentence should be actionable or give necessary
context.
