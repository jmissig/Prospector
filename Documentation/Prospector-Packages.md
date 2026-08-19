# Prospector package format

A `.prospector` document is a package directory containing a versioned manifest and one or more USDZ models. Apple Files presents the directory as one tappable document.

```text
My Models.prospector/
├── manifest.json
├── Model-A.usdz
└── Model-B.usdz
```

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
- `category` is optional and reserved for future grouping in the picker.
- `startPose` is optional. Position values are meters in authored model coordinates; yaw is in radians.

Malformed manifests, missing assets, unsupported versions, and paths outside the package produce a visible error instead of replacing the active catalog or crashing.

## Position state

Prospector writes a human-readable `state.json` beside `manifest.json`. It records the current model, a UTC timestamp, and the last position and yaw for each viewed model:

```json
{
  "currentModelID": "model-a",
  "formatVersion": 1,
  "modelStates": [
    {
      "modelID": "model-a",
      "updatedAt": "2026-08-19T07:21:03Z",
      "viewerPositionMeters": {
        "x": 12.4,
        "y": 1.7,
        "z": -8.2
      },
      "yawRadians": 1.57
    }
  ],
  "updatedAt": "2026-08-19T07:21:03Z"
}
```

Writes occur two seconds after movement stops, at most once every 30 seconds during continuous movement, and when switching models, leaving immersive space, opening another package, or backgrounding the app.

If `state.json` is malformed, Prospector leaves it untouched and disables position writes for that package. A persistence failure does not prevent the models from loading.

To turn a captured location into an authored starting position, copy that model's pose from `state.json` into its `startPose` in `manifest.json`. Prospector never promotes transient state into the authored manifest automatically.
