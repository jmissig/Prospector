# Optional surrounding terrain — implementation plan

Status: first visual-only increment implemented locally on 2026-09-25; focused automated checks and the visionOS Simulator build passed. Real terrain registration, panorama interaction, and Vision Pro performance remain open. Baseline: v1.6.

## Goal and boundaries

Extend the detailed property into a coarse surrounding landscape, with real land shape and parallax, while preserving authored building/site geometry, scale, saved locations, navigation, and the distant environment. Terrain and imagery travel inside the private `.prospector` package; no private assets enter this repository.

First deliverable: one reduced-detail terrain USDZ shared by multiple designs, visual-only, loaded after the house becomes usable. No new settings UI, GIS engine, terrain editor, network dependency, tile streaming, or dynamic level-of-detail system. Optional walkable terrain is a second gated increment, not a prerequisite for scenery.

Existing-solutions preflight: use the existing package loader, RealityKit asset loading, USDZ pipeline, and collision compiler where applicable. No additional runtime library is needed for this scope. Geographic reprojection, clipping, simplification, and texture preparation belong in the external asset-preparation workflow, using its established GIS tools rather than a new Prospector conversion system.

## Current code seams

- `ProspectorDocument.swift`: versioned manifest decoding, relative-path validation, coordinated reads, security-scoped package lifetime.
- `ModelCatalog.swift`: explicit model descriptors, selection and load state. Add separate optional terrain status/warning; do not mark a usable house as failed because scenery failed.
- `ImmersiveView.swift`: model replacement and cancellation, navigation transform, imported-model coordinate conversion, floor probes, teardown. Current probes target the house/site entity only.
- `LandscapeEnvironment.swift`: package panorama, already in Y-up navigation coordinates. Current landscape is a finite spherical shell with radius derived from its landmark offset, not an infinitely distant sky.
- `Tools/ProspectorCollisionCompiler/main.swift`: optional collision-bearing derivatives. Do not use its all-mesh collision generation indiscriminately for distant visual terrain.

## Proposed package contract

Keep format version 1 with optional fields so existing packages work unchanged and older apps ignore terrain. One package-level `terrains` list defines assets; each model optionally selects one using `terrainID` and supplies its placement. This is a small typed list and lookup, not a general asset registry.

Manifest fragment (implemented visual-only keys):

```json
{
  "terrains": [
    {
      "id": "surroundings",
      "path": "Terrain/surroundings.usdz"
    }
  ],
  "models": [
    {
      "id": "design-a",
      "name": "Design A",
      "path": "Design A.usdz",
      "terrainID": "surroundings",
      "terrainPlacement": {
        "translationMeters": [0, 0, 0],
        "yawRadians": 0
      }
    }
  ]
}
```

- Missing `terrainID`: no surrounding terrain. Missing placement: identity. Placement without a terrain reference is invalid.
- Require unique nonempty terrain IDs, valid references, finite translation/yaw, and contained relative `.usdz` paths. Resolve symlinks using existing package rules. Reject unsafe paths and malformed configuration during package validation.
- Missing or undecodable optional terrain assets produce a nonfatal warning and house-only viewing. Distinguish invalid configuration from runtime file availability; do not weaken validation for house assets.
- All referenced textures must be packaged, preferably inside USDZ; no external URLs or dependencies on the author's filesystem.
- One physical asset can serve multiple designs, but only when alignment and cutout are genuinely compatible. Different site extents may require distinct terrain exports or a validated common cutout.
- Add optional `compiledPath` only when a measured loading benefit justifies it. Source USDZ remains authoritative; derive again when it changes. A visual-only derivative must not require complete collision coverage.
- Terrain placement never changes a model's authored transform or position sidecar. Terrain has no separate viewer pose or saved locations.

## Asset handoff and alignment

The data-preparation thread should deliver:

1. A locally centered, meter-scaled Y-up terrain USDZ, with no baked geographic-scale translation. Record horizontal axis directions and handedness explicitly; do not assume the building's negative Z is true north.
2. A source/provenance note: dataset and license, acquisition date, resolution, horizontal CRS, vertical datum and units, geographic anchor, and the exact conversion to local coordinates. Resolve geoid/ellipsoid and feet/meters differences upstream, with uncertainty recorded.
3. Measured registration against the detailed site: at least three distributed control points, including elevation checks. Record residuals and a tolerance justified by the source resolution; the app cannot infer accuracy from a plausible appearance.
4. The detailed-site footprint and coarse-terrain exclusion polygon. Preserve the detailed site untouched. Cut the coarse mesh outside that footprint and author a transition band on the coarse side; avoid coincident faces, cracks, visible cliffs, and terrain covering the building. Validate each design, not only a single lot boundary.
5. Bounds, vertex/triangle counts, material count, texture dimensions and decoded-memory estimate, file size, plus reference views showing the seam and horizon. Use progressively coarser sampling with distance in the exported mesh; that need not imply runtime LOD.
6. Suggested per-model translation/yaw and known limitations. Unresolved registration or vertical-datum issues block an alignment claim, not investigation of loading.

Imported terrain normalization happens once. Compose transforms explicitly:

`sceneFromTerrain = sceneFromNavigation × navigationFromTerrainPlacement × terrainImportNormalization`

The normalized terrain uses meters and Y-up; placement contains only translation and yaw, not ad hoc rescaling or vertical exaggeration. Verify import normalization with a synthetic axis/scale fixture so the USD loader's root transform is not applied twice. Apply the latest navigation transform before making an asynchronously loaded layer visible, and mark it dirty after attachment.

## Scene behavior and ownership

- Keep separate house/site, terrain, and panorama entities. Terrain is excluded from house bounds, initial floor calibration, and saved-location recalibration in the first increment.
- Existing hide-model gesture hides the house/site only. Terrain and panorama stay visible. Terrain has no input targets and must not intercept taps or acquire collisions merely to support gestures.
- `prospector.useMeadowEnvironment` continues to select the backdrop only; it does not silently disable terrain.
- Finish house loading and enable navigation before beginning optional terrain loading. Use one bounded scenery task, not unbounded parallel loads. Do not opportunistically redesign panorama loading in this change.
- Associate each task with package revision and selected model request; retain that package's security scope until work actually finishes. Cancellation checks after awaited RealityKit calls must prevent late results from attaching to a newer model/package.
- Reuse the attached terrain across compatible same-package design switches when asset identity is unchanged; update placement. Release outgoing terrain before loading a different asset. No multi-terrain resident cache in the first version.
- On exit, package replacement, or selection without terrain: cancel work, detach entities, clear warning/status, and release resources. Cancellation is not a user-visible load failure.
- Optional terrain failure leaves the house, locations, controls, and backdrop usable, with a concise warning using the existing launch-window error presentation pattern. No new settings controls.

## Terrain versus panorama

Do not use the panorama's nominal radius as a DEM coverage requirement. Pick terrain extent and resolution from needed views and available data.

Before shipping, check terrain bounds against the existing finite shell from all intended viewing positions. Terrain outside the opaque shell may be hidden, and photographed mountains may duplicate actual modeled ridges. Do not silently enlarge the shell: its radius participates in the landmark placement calibration. If the assets conflict, revise the terrain extent or prepare a compatible backdrop/calibration upstream. A separate sky-only or horizon-compositing feature is follow-up scope if those simple approaches cannot produce a coherent result. Check distant clipping and depth precision on headset, not just the Mac.

## Optional walkable terrain — second increment

Only enable after the visual layer is aligned and its real performance is measured.

- Add an optional simplified collision asset/path, sharing the exact visual terrain coordinate frame and property exclusion. Omission means visual-only, with no runtime generation across the full distant mesh.
- Generate static triangle collisions offline and verify export/reload coverage. Avoid convex fallback that bridges valleys or cutouts; report failures rather than silently changing walkable shape.
- Extend surface queries explicitly to house/site and surrounding terrain using their respective coordinate transforms. Preserve current site-floor selection and upper-floor behavior. Use surrounding terrain only outside the authored-site exclusion; never choose it merely because a house probe missed an opening.
- Keep height reset, terrain follow, automatic calibration, and saved-location jumps consistent. No-hit behavior stays unchanged; a collision asset appearing late must not teleport the viewer.
- Define and test failure handling: visual terrain can remain if its optional collision derivative is unavailable, with a warning and no false promise of walkability.

## Implementation sequence and acceptance

### 1. Contract and aligned sample

Implement optional manifest fields, descriptor, package validation, and a small synthetic terrain fixture. Agree on the private data handoff before coupling app work to a large real export.

Checks: absent terrain is backward-compatible; shared references and per-model placement resolve; duplicate/unknown IDs, nonfinite transforms, absolute paths, traversal, and symlink escapes are rejected; missing optional files remain nonfatal. Decode existing model position sidecars unchanged.

### 2. Visual terrain lifecycle

Load and attach the layer after the house; handle status, failure isolation, navigation transforms, compatible reuse, cancellation, and teardown.

Checks: meter/axis fixture and nonzero translation/yaw; movement and repeated location jumps keep terrain/site aligned; terrain attachment while already moving uses the current pose. Rapid model switching, closing mid-load, replacing a package, and re-entering immersion never leave stale or duplicate terrain. Hidden house does not hide terrain; taps and floor calibration remain unchanged. Meadow override still works.

### 3. Real asset and hardware gate

Validate the site transition, all model placements, horizon/shell interaction, authored scale, and material appearance. Measure time to usable house, terrain-ready time, peak/steady memory, draw calls, frame time/dropped frames, and repeated-switch memory behavior against v1.6 house-only viewing on the same headset.

Do not invent a universal triangle or memory limit now. Record measured budgets and optimize the exported asset first if it exceeds acceptable interactive performance. Simulator build success is necessary but not evidence of headset comfort, seam correctness, or distant rendering correctness.

### 4. Optional collisions, only if needed

Add the explicit collision contract and surface-query integration described above. Test slopes, cutout boundaries, no-hit cases, upper floors, and transitions both directions. Add compiler support only for the agreed terrain collision representation.

For implementation commits: run focused manifest/transform/lifecycle checks, the repository's visionOS Simulator build, and `git diff --check`. Update `Prospector-Packages.md`, README, and relevant contributor notes once behavior exists. Keep private data, coordinates, screenshots, and calibration records outside public Git. Release/version/tagging is a separate requested action.

## Definition of done for the first release

One optional shared terrain asset travels with the package, is correctly aligned, appears without blocking house use, survives normal navigation/model switching, and cannot alter house geometry, floor selection, gestures, or persisted locations. Missing scenery is recoverable. Actual headset evidence and measured performance are recorded, or the unverified portions are explicitly left open. Streaming, GIS interpretation, automatic cutouts, new terrain UI, and walkability are not implied by completion of this first release.

## Primary references

- [Apple: asynchronous Entity file loading](https://developer.apple.com/documentation/realitykit/entity/init(contentsof:withname:)) — supports the existing USDZ/Reality asset-loading approach.
- [Apple: generateStaticMesh(from:)](https://developer.apple.com/documentation/realitykit/shaperesource/generatestaticmesh(from:)) — relevant only to the optional collision increment.
- Local: [package format](Prospector-Packages.md), [performance backlog](../PERFORMANCE.md), and the code seams above.

## Implementation verification — 2026-09-25

- `Tools/TerrainChecks/run.sh`: passed legacy-package decoding, opt-in/shared/missing terrain, ID/path/symlink/finite-placement validation, transform composition, recursive collision/input removal, compatible reuse, no-terrain switching, serialized decoding, stale-request rejection, teardown, and nonfatal failures. A real packaged USD fixture verifies meter scale, Y-up, imported root translation, and placement exactly once; a real absent file verifies recovery.
- `xcodebuild -project Prospector.xcodeproj -scheme Prospector -sdk xrsimulator -destination 'generic/platform=visionOS Simulator' build`: passed using repo-local derived data.
- No aligned private terrain asset was added, and no app was installed or deployed. Real-site cutouts, panorama compatibility, headset interactions, visual presentation of warnings, and performance remain unverified.
- Compiled terrain and surrounding-terrain collisions remain deferred. The existing house collision and position-persistence paths were not changed.
