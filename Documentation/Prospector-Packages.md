# Prospector package format

A `.prospector` document is a package directory containing a versioned manifest and one or more USDZ models. Apple Files presents the directory as one tappable document.

```text
My Models.prospector/
├── manifest.json
├── Model-A.usdz
├── Model-A.state.json
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
- `statePath` is optional but recommended. It must remain inside the package and end in `.state.json`. When omitted, Prospector derives it from the model path (for example, `Model-A.usdz` becomes `Model-A.state.json`).
- `category` is optional and reserved for future grouping in the picker.
- `startPose` is optional. Position values are meters in authored model coordinates; yaw is in radians.

Malformed manifests, missing assets, unsupported versions, and paths outside the package produce a visible error instead of replacing the active catalog or crashing.

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

Saved locations contain position only. Jumping to one leaves the model's current yaw unchanged. New locations are named `Location 1`, `Location 2`, and so on; names remain stable after deletion and can be edited directly in the sidecar.

If a model state sidecar is malformed, Prospector leaves it untouched and disables writes for that model. A persistence failure does not prevent the model from loading.

To turn a captured location into an authored starting position, copy that model's pose from its sidecar into `startPose` in `manifest.json`. Prospector never promotes transient state into the authored manifest automatically.

## Terrain-probe diagnostics

Pressing D-pad **Up** appends diagnostic entries to `terrain-probe.jsonl` at the package root. Each line is an independent JSON object so an interrupted write does not invalidate earlier entries.

The log records the active model and reset-request revision, navigation and physical-device positions, model- and navigation-space ray endpoints, every raw collision hit and transformed normal, rejection reasons, the selected height, and whether Prospector applied the zero-height fallback. Multiple entries with the same `resetRequestRevision` show that one physical button press was processed on multiple scene-update frames.

The file is runtime diagnostic data, not part of the authored manifest. It can be removed when it is no longer needed; Prospector creates it again on the next D-pad Up request.
