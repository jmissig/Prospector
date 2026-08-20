# Prospector

A little visionOS app for walking around inside large USDZ models (house scans, terrain, etc.) on Apple Vision Pro, with game controller support for movement.

This is a small fork of Christian's app. Christian says:

> I built this for myself (well, I vibe coded it so if any code is janky please don't yell at me), so it's rough around the edges and not the most straightforward to use, but it should be a fun starting point if you want to explore your own large models in an immersive space.

## What's added in this fork

This fork keeps Christian's controller-driven USDZ viewer and adds:

- **Multi-model document packages.** Open one local `.prospector` package from Files to load and switch among multiple USDZ models without embedding private assets in the app. Packages can optionally include Mac-precompiled `.reality` models while retaining USDZ fallback; Vision Pro testing confirmed that the compiled models load dramatically faster.
- **Persistent model state and saved locations.** Each model keeps its own resume position and named locations in a readable JSON sidecar. Add locations in immersive view and jump among them with the panel or controller. Prospector attempts to land on a model surface after loading and reuses that session calibration across the model's saved locations.
- **In-app controller guidance.** A spatial cheat sheet uses the connected controller's labels and glyphs when available, while brief HUD messages confirm location jumps and mode changes.
- **Progressive immersion.** Use the Digital Crown to move between a peripheral view of the real world and full immersion.
- **Faster, safer model lifecycles.** Model switching releases the outgoing model before loading its replacement, cancels stale work, and manages RealityKit and ARKit resources explicitly.
- **Architectural USDZ coordinate fixes.** Collision probing and terrain following correctly account for Z-up USDZ files, imported root transforms, model scale, and the viewer's physical position.

## Setup

1. Set your development team in the project's Signing & Capabilities settings.
2. Build and run on Apple Vision Pro (visionOS 26.2+).
3. Put a `.prospector` package in iCloud Drive and tap it in Files.

Prospector opens the package, selects its default model, and makes every model in its manifest available in the launch-window picker. It keeps only one model loaded at a time and preserves per-model navigation positions and controller modes while switching.

The immersive view starts partially immersed. Turn the Digital Crown to reveal more of the real world around the periphery or expand the model to full immersion.

Prospector automatically resumes each model's last position when saved state is available, otherwise it uses the model's manifest starting position.

The repository remains asset-free. A placeholder bundled-model catalog is available for development, but normal use does not require embedding USDZ files in the app or committing them to Git.

## Prospector packages

A `.prospector` document is a folder that Files presents as one tappable package:

```text
My Models.prospector/
├── manifest.json
├── Model-A.usdz
└── Model-B.usdz
```

Create the folder, copy your USDZ files into it, add a `manifest.json`, then give the folder a `.prospector` extension. A minimal manifest looks like this:

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
      "path": "Model-B.usdz"
    }
  ]
}
```

For optional starting positions, generated per-model state sidecars, compiled `.reality` models, and the complete format and validation rules, see [Prospector package format](Documentation/Prospector-Packages.md).

### Precompiling collisions

Compiled `.reality` models can be authored visually with Apple's Reality Composer Pro by importing the USDZ, configuring its collision components, and saving the compiled scene beside the source model. This is also well suited to agent-driven or automated preparation: the included Mac compiler performs Prospector's exact recursive collision generation, exports the result, reloads it, and verifies that every mesh-bearing entity retained its collision component. This repository's first compiled package models were generated and validated through that agent-operated workflow.

Whichever workflow you use, keep the original USDZ as the source of truth and fallback. See [Prospector package format](Documentation/Prospector-Packages.md#generate-a-compiled-realitykit-model) for the compiler commands and manifest setup.

### Optional bundled models

For development builds, you can still drag USDZ files into the `Prospector` folder in Xcode and add matching `ModelDescriptor` values to `ModelCatalog.models`. Those bundled entries are shown until a `.prospector` package is opened.

## Controls

Pair a game controller (e.g. a Nintendo Switch Pro Controller, DualSense, or Xbox controller) with your Vision Pro. Movement is relative to the direction you're looking.

| Input | Action |
| --- | --- |
| Left thumbstick | Move |
| Right thumbstick | Virtual turn (yaw) |
| Left / right trigger | Move down / up |
| D-pad up | Land on a model surface and calibrate saved-location heights for the session |
| D-pad right | Toggle terrain follow (height snaps to the ground as you move) |
| D-pad left | Toggle speed mode (6× movement) |
| A | Show or dismiss saved locations |
| X / Y | Jump to the previous / next saved location |

Press A to show the saved-locations panel on the left. A separate controller guide appears below your view, using the connected controller's own button labels and glyphs when available. The panels use your current viewpoint for their initial placement, then remain fixed in the immersive world instead of following your head. The guide includes the stick, trigger, and complete D-pad mapping so the controls do not need to be memorized.

While the panels are visible, movement and turning inputs are paused; use look-and-pinch to choose a location, add the current position, or dismiss the locations panel. Press A again for a reliable controller-only dismissal. Saved locations cannot be deleted in the immersive panel, preventing accidental removal.

You can also pinch your thumb and middle finger together for half a second (either hand) to toggle the model's visibility.

## Development

See [PERFORMANCE.md](PERFORMANCE.md) for the current performance review and Vision Pro profiling plan.

See [TODO.md](TODO.md) for current product and hardware follow-ups.

## Credits

The environment skybox is the [Meadow 2](https://polyhaven.com/a/meadow_2) HDRI from Poly Haven (CC0).
