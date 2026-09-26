# Prospector package format

A `.prospector` document is a package directory containing a versioned manifest and one or more USDZ models. Apple Files presents the directory as one tappable document.

```text
My Models.prospector/
├── manifest.json
├── Model-A.usdz
├── Model-A.reality
├── Model-A.state.json
└── Model-B.usdz
```

## Optional photographic panorama

There are two backdrop choices: a **standard equirectangular photograph** or the
original bundled **Meadow**. The former landmark/rock-stretch mapping is removed.
Omitting `environment`, omitting its `projection`, or specifying
`"projection": "meadow"` selects Meadow. This deliberately supersedes the old
implicit landmark mapping: existing packages still open, but their old
landmark-configured backgrounds now show Meadow until explicitly migrated.
Unknown projection names are rejected, not guessed. Do not use this new
manifest with an older app that only understands the former environment schema.

For a photographic panorama, add this object to the model entry:

```json
"environment": {
  "projection": "equirectangular",
  "texturePath": "Environment/photographic-panorama-8k.png",
  "referencePositionMeters": [0, 0, 0],
  "radiusMeters": 2000,
  "yawOffsetRadians": 0
}
```

- `texturePath`: a package-relative PNG/JPEG. Absolute paths and symlink escapes
  are rejected. A missing or unreadable image falls back to Meadow at runtime,
  with a visible status message; the house remains usable.
- `referencePositionMeters`: finite `[x,y,z]` shell center in **Y-up navigation
  meters before user translation/yaw**, not raw USDZ coordinates.
- `radiusMeters`: finite shell radius, 100–100,000 meters. Positioning remains a
  finite distant sphere, not a head-locked or infinite-distance cubemap.
- `yawOffsetRadians`: optional finite horizontal alignment offset, default `0`.
  It never changes latitude, center, radius, or saved poses.
- `landmarkUV` and `landmarkOffsetMeters` no longer participate in mapping. Extra
  old fields are ignored. Landmark elevation must already be baked into the image.

### Projection and true-north alignment

Image coordinates use the **top-left** origin, `u` increasing rightward and `v`
increasing downward. Latitude is exactly `π/2 − πv`: top **+90°**, middle **0°**,
bottom **−90°**. There is no anchor, special row, or latitude stretch.

At zero yaw, the center of the image (`u=0.5`) faces navigation **−Z**. `u=0.75`
faces **+X**, `u=0.25` faces **−X**, and both seam edges (`u=0` and `u=1`) face
**+Z**. Positive yaw turns the image-center bearing from −Z toward +X
(clockwise viewed from above, with −Z drawn upward); `+π/2` makes the image
center face +X. This is an azimuth convention, not the positive right-handed
+Y rotation convention used by terrain placement.

To align a known true-north column `uNorth` to the model's north bearing `bNorth`
(measured from −Z toward +X), set:

```text
yawOffsetRadians = bNorth − 2π × (uNorth − 0.5)
```

For example, if model −Z is true north and the north column is `uNorth=0.25`,
use `yawOffsetRadians = 1.57079632679`. The app does not infer geographic north.

### Resolution, loading and reporting

Use **8192×4096** where possible. **4096×2048** is the supported lower-resolution
alternative (point `texturePath` at that image). Equirectangular images must be
2:1 and at least 4096×2048. The app does not rewrite, resize or generate imagery.
It reads source dimensions through ImageIO and compares them with the actual
loaded `TextureResource.width`/`height`, reporting both in the launch window and
in one Environment-category console entry per successful texture load.

If RealityKit returns smaller dimensions, the status explicitly reports the
change. A loaded 4096×2048 resource is accepted; below that minimum or with a
non-2:1 aspect ratio, the backdrop falls back to Meadow with an explanation.
Decode/resource failures also use Meadow, not the retired stretch mapping.
Invalid configuration (unsafe paths, nonfinite placement, invalid radius, unknown
mode) still rejects the manifest. Meadow retains its original bundled texture
and is not subject to the photographic panorama's minimum size.

Source/loaded dimensions describe the base texture, not the mip level chosen
by the renderer at a particular viewing distance. GPU texture limits and memory
pressure are device-specific; API support or a Mac test is not a headset
performance guarantee.

The unlit panorama follows existing virtual translation/yaw, stays visible when
hiding the house, and is excluded from house bounds, input targets, collisions,
floor calibration and persistence. Switching or closing removes it as before.

### Verification

Run `sh Tools/PanoramaChecks/run.sh` for synthetic-only Mac checks: manifest
selection, legacy-to-Meadow compatibility, validation, horizon/poles/linear
latitude, seam/handedness, yaw alignment, actual 4K/8K texture loading, shell
position/radius and absence of collision/input components. No private assets
are used or altered.

2026-09-26 Mac observations: **4096×2048 → 4096×2048** and
**8192×4096 → 8192×4096**, no observed downsampling. The visionOS Simulator
build is a compile/link check, not a rendered simulator check. **Headset visual
orientation, texture resolution under device memory pressure, horizon alignment,
navigation and frame-time verification remain outstanding.**

### Hidden Meadow override

The app reads the Boolean UserDefaults key `prospector.useMeadowEnvironment` each time a model loads. `true` skips loading the package panorama and shows the original bundled Meadow skybox; `false` (or an absent key) uses the package landscape when provided, otherwise Meadow. There is no UI control, and package imagery/calibration remains untouched. Explicit equirectangular manifest validation still applies; legacy/missing-mode environments simply select Meadow.

For a temporary Xcode run, add these two launch arguments to the scheme:

```text
-prospector.useMeadowEnvironment YES
```

Remove the arguments to return to normal package selection. To persist the override, set the same Boolean key in the app's own UserDefaults domain; remove it or set it to `false` to restore normal behavior. A Mac `defaults` command does not change preferences on Vision Pro. Reload the model or reopen immersion after changing the preference.

## Optional surrounding terrain

Terrain is strictly opt-in. Existing packages need no changes. To include visual-only surroundings, define a shared asset in the top-level `terrains` array and select it on individual models:

```json
"terrains": [
  { "id": "surroundings", "path": "Terrain/surroundings.usdz" }
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
```

Omit `terrainID` for no terrain; omit `terrainPlacement` for identity placement. Multiple designs can share one asset with different placements. `terrainPlacement` without `terrainID`, unknown/duplicate IDs, unsafe paths, and malformed/nonfinite placements are rejected. Paths must be relative contained USDZ paths, without `..` or escaping symlinks. No terrain assets are required unless explicitly referenced; an absent or unreadable referenced USDZ does **not** prevent house loading. A short nonfatal warning appears in the launch window instead. Invalid configuration remains an error, not permission to read outside the package.

Prepare terrain in local meters, Y-up, with geographic reprojection and vertical-datum conversion done upstream. Placement applies positive right-handed yaw about +Y, followed by translation in navigation coordinates. The imported USD root transform is preserved once, beneath this placement. Do not bake large geographic coordinates into the mesh. Keep textures inside USDZ and preserve the original authored house/site assets. See [the terrain plan](Terrain-Plan.md#asset-handoff-and-alignment) for registration and property-cutout requirements.

The house becomes usable before optional terrain loading begins. Terrain follows navigation, remains visible when hiding the house, and is reused across same-package designs referencing the same asset. Changing packages or exiting releases it; canceled results cannot attach to a newer selection. No surrounding-terrain collision, physics, or input components are retained, so it cannot affect floor calibration, terrain following, location jumps, or tap navigation. Saved locations remain house-model state.

The Meadow override affects the backdrop only. This release does not alter panorama radius or stitch terrain to the detailed site; the author must validate the transition and finite panorama shell together. Missing terrain does not remove the backdrop. Compiled terrain, walking on coarse terrain, streaming, and automatic GIS alignment are not implemented.

## Manifest

Manifest format version 1:

```json
{
  "formatVersion": 1,
  "name": "My Models",
  "defaultModelID": "model-a",
  "models": [
    {
      "id": "model-a",
      "name": "Model A",
      "path": "Model-A.usdz",
      "compiledPath": "Model-A.reality",
      "statePath": "Model-A.state.json",
      "startPose": {
        "viewerPositionMeters": {
          "x": 4.1,
          "y": 2.0,
          "z": 16.8
        },
        "yawRadians": -0.35
      }
    },
    {
      "id": "model-b",
      "name": "Model B",
      "path": "Model-B.usdz",
      "category": "Site Models"
    }
  ]
}
```

Requirements:

- `formatVersion` must be `1`.
- `name`, every model `id`, and every model `name` must be nonempty.
- Model IDs must be unique, and `defaultModelID` must match one of them.
- Each `path` must be relative, remain inside the package, and point to an existing `.usdz` file.
- `compiledPath` is optional. It must remain inside the package and end in `.reality`. When the file exists and contains collision components for every mesh-bearing model entity, Prospector loads it instead of the USDZ and skips runtime collision generation. A missing, unreadable, or incomplete compiled file falls back to `path` and the normal USDZ collision-generation path.
- `statePath` is optional but recommended. It must remain inside the package and end in `.state.json`. When omitted, Prospector derives it from the model path (for example, `Model-A.usdz` becomes `Model-A.state.json`).
- `category` is optional and reserved for future grouping in the picker.
- `startPose` is optional. Position values are meters in authored model coordinates; yaw is in radians.

Malformed manifests, missing assets, unsupported versions, and paths outside the package produce a visible error instead of replacing the active catalog or crashing.

## Generate a compiled RealityKit model

Prospector includes a small macOS command-line compiler that performs the same recursive collision setup as the visionOS runtime, writes the complete visual-and-collision hierarchy as `.reality`, reloads it, and verifies that all collision components survived serialization.

Build the compiler from the repository root:

```sh
mkdir -p .build/tools
xcrun --sdk macosx swiftc \
  -O \
  -parse-as-library \
  -framework RealityKit \
  Tools/ProspectorCollisionCompiler/main.swift \
  -o .build/tools/prospector-collision-compiler
```

Generate or replace a compiled model:

```sh
.build/tools/prospector-collision-compiler \
  "/path/My Models.prospector/Model-A.usdz" \
  "/path/My Models.prospector/Model-A.reality"
```

The command prints a JSON report containing collision counts, timings, and output size. After it succeeds, add the relative `compiledPath` to that model's manifest entry. Keep the USDZ in the package: it remains the source of truth and the runtime fallback.

Regenerate the `.reality` file whenever its USDZ changes. Prospector validates the compiled hierarchy's collision coverage, but it does not hash large source models on Vision Pro and therefore cannot detect a visually valid but stale cache automatically.

## Position state

Prospector writes one human-readable state sidecar per model. It records the model's last position and yaw plus its saved locations:

```json
{
  "formatVersion": 1,
  "modelID": "model-a",
  "savedLocations": [
    {
      "createdAt": "2026-08-19T07:10:00Z",
      "id": "9C38A150-15B7-4B31-9359-ECC711FF70B0",
      "name": "Location 1",
      "viewerPositionMeters": {
        "x": 4.1,
        "y": 2.0,
        "z": 16.8
      }
    }
  ],
  "updatedAt": "2026-08-19T07:21:03Z",
  "viewerPositionMeters": {
    "x": 12.4,
    "y": 1.7,
    "z": -8.2
  },
  "yawRadians": 1.57
}
```

Writes occur two seconds after movement stops, at most once every 30 seconds during continuous movement, and when switching models, leaving immersive space, opening another package, or backgrounding the app.

Saved locations contain position only. Jumping to one leaves the model's current yaw unchanged. New locations are named `Location 1`, `Location 2`, and so on. They cannot be deleted from the immersive panel; names and deliberate removals can be edited directly in the sidecar.

If a model state sidecar is malformed, Prospector leaves it untouched and disables writes for that model. A persistence failure does not prevent the model from loading.

To turn a captured location into an authored starting position, copy that model's pose from its sidecar into `startPose` in `manifest.json`. Prospector never promotes transient state into the authored manifest automatically.
