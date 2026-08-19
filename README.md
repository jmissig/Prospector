# Prospector

A little visionOS app for walking around inside large USDZ models (house scans, terrain, etc.) on Apple Vision Pro, with game controller support for movement.

I built this for myself (well, I vibe coded it so if any code is janky please don't yell at me), so it's rough around the edges and not the most straightforward to use, but it should be a fun starting point if you want to explore your own large models in an immersive space.

## Setup

1. Set your development team in the project's Signing & Capabilities settings.
2. Build and run on Apple Vision Pro (visionOS 26.2+).
3. Put a `.prospector` package in iCloud Drive and tap it in Files.

Prospector opens the package, selects its default model, and makes every model in its manifest available in the launch-window picker. It keeps only one model loaded at a time and preserves your current navigation position and controller modes while switching.

The repository remains asset-free. A placeholder bundled-model catalog is available for development, but normal use does not require embedding USDZ files in the app or committing them to Git.

## Prospector packages

A `.prospector` document is a folder that Files presents as one tappable package:

```text
My Models.prospector/
├── manifest.json
├── Model-A.usdz
└── Model-B.usdz
```

Create the folder, place `manifest.json` and the referenced USDZ files inside it, then give the folder a `.prospector` extension. Keep model paths relative to the package root.

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
      "path": "Model-A.usdz"
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
- Each `path` must stay inside the package and point to an existing `.usdz` file.
- `category` is optional and reserved for future grouping in the picker.

Malformed manifests, missing assets, unsupported versions, and paths outside the package produce a visible error instead of replacing the active catalog or crashing.

### Optional bundled models

For development builds, you can still drag USDZ files into the `Prospector` folder in Xcode and add matching `ModelDescriptor` values to `ModelCatalog.models`. Those bundled entries are shown until a `.prospector` package is opened.

## Controls

Pair a game controller (e.g. a DualSense or Xbox controller) with your Vision Pro. Movement is relative to the direction you're looking.

| Input | Action |
| --- | --- |
| Left thumbstick | Move |
| Right thumbstick | Look (yaw) |
| Left / right trigger | Move down / up |
| D-pad up | Reset height to the terrain surface |
| D-pad right | Toggle terrain follow (height snaps to the ground as you move) |
| D-pad left | Toggle speed mode (6× movement) |

You can also pinch your thumb and middle finger together for half a second (either hand) to toggle the model's visibility.

## Credits

The environment skybox is the [Meadow 2](https://polyhaven.com/a/meadow_2) HDRI from Poly Haven (CC0).
