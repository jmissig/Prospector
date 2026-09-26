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

## Optional distant landscape

Each model can include an `environment` object. Omit it to retain the bundled meadow. Older app versions ignore this optional field.

```json
"environment": {
  "texturePath": "Environment/landscape.png",
  "referencePositionMeters": [0, 0, 0],
  "landmarkOffsetMeters": [0, 300, -2000],
  "landmarkUV": [0.5, 0.45]
}
```

Supply a 2:1 equirectangular PNG/JPEG inside the package; absolute paths and symlink escapes are rejected. Coordinates are **Y-up navigation meters before user movement/yaw**, not raw USDZ coordinates. Establish the model's north/origin separately; this feature does not georeference models automatically.

`landmarkUV` identifies a known point in the image using normalized top-left-origin coordinates, strictly inside (0,1). `landmarkOffsetMeters` places that point relative to `referencePositionMeters`. Its length sets the shell radius (100–100,000 m). Longitude wraps through the anchor; latitude is piecewise linearly mapped through the anchor and the poles. This anchors one landmark, not every mountain's size or distance. Generated panoramas remain illustrative, not visibility studies.

The unlit landscape replaces the meadow, follows virtual translation/yaw, and is excluded from model bounds, input targets, and terrain collisions. Model visibility toggling leaves scenery visible. Switching or closing removes the outgoing landscape. Invalid calibration fails package opening; texture decoding errors appear in the model-loading error. Private textures belong in packages, never the app repository.

### Hidden Meadow override

The app reads the Boolean UserDefaults key `prospector.useMeadowEnvironment` each time a model loads. `true` skips loading the package panorama and shows the original bundled Meadow skybox; `false` (or an absent key) uses the package landscape when provided, otherwise Meadow. There is no UI control, and package imagery/calibration remains untouched. Package manifest validation still applies.

For a temporary Xcode run, add these two launch arguments to the scheme:

```text
-prospector.useMeadowEnvironment YES
```

Remove the arguments to return to normal package selection. To persist the override, set the same Boolean key in the app's own UserDefaults domain; remove it or set it to `false` to restore normal behavior. A Mac `defaults` command does not change preferences on Vision Pro. Reload the model or reopen immersion after changing the preference.

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
