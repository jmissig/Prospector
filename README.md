# Prospector

Prospector is a visionOS app for experiencing house-sized USDZ models at 1:1 scale on Apple Vision Pro. It lets you stand inside an architectural model, see it from different vantage points, and move between those viewpoints without losing your sense of physical grounding.

When a model opens, Prospector finds a floor or other walkable surface beneath the starting point and aligns it with your real floor. That collision data can be generated on Vision Pro or precomputed in Reality Composer Pro for much faster loading.

A game controller lets you move freely through the model, including turning, changing height, and following the terrain. Continuous virtual movement can be uncomfortable, though, so Prospector also lets you save places that feel useful and jump instantly between them. Once those locations are saved, you can move to the next one with a double tap—no controller required—and then simply look around.

Use the Digital Crown to choose how present the model feels: view it through a portal with the real world around you, or become fully surrounded by it.

## About this fork

Prospector is a fork of [Christian Selig's original app](https://github.com/christianselig/Prospector). Christian describes it this way:

> I built this for myself (well, I vibe coded it so if any code is janky please don't yell at me), so it's rough around the edges and not the most straightforward to use, but it should be a fun starting point if you want to explore your own large models in an immersive space.

## What's added in this fork

This fork keeps Christian's controller-driven USDZ viewer and adds:

- **Multi-model document packages.** Open one local `.prospector` package from Files to load and switch among multiple USDZ models without embedding private assets in the app. Packages can optionally include Mac-precompiled `.reality` models while retaining USDZ fallback; Vision Pro testing confirmed that the compiled models load dramatically faster.
- **Persistent model state and saved locations.** Each model keeps its own resume position and named locations in a readable JSON sidecar. Add locations in immersive view and jump among them with the panel or controller. Prospector attempts to land on a model surface after loading and recalibrates the session height at each saved-location jump.
- **In-app controller guidance.** A spatial cheat sheet uses the connected controller's labels and glyphs when available, while brief HUD messages confirm location jumps and mode changes.
- **Progressive immersion.** Use the Digital Crown to move between a peripheral view of the real world and full immersion.
- **Faster, safer model lifecycles.** Model switching releases the outgoing model before loading its replacement, cancels stale work, and manages RealityKit and ARKit resources explicitly.
- **Architectural USDZ coordinate fixes.** Collision probing and terrain following correctly account for Z-up USDZ files, imported root transforms, model scale, and the viewer's physical position.

## Getting started

1. Set your development team in the project's Signing & Capabilities settings.
2. Build and run on Apple Vision Pro (visionOS 26.2 or later).
3. Open a `.prospector` package from Files.

Prospector selects the package's default model and makes its other models available in the launch window. Each model resumes where you left it when saved state is available; otherwise it starts from the position defined by the package.

For how to assemble a package, add optional starting positions, or precompile collision data for faster loading, see [Prospector package format](Documentation/Prospector-Packages.md).

## Moving through a model

Pair a game controller, such as a Nintendo Switch Pro Controller, DualSense, or Xbox controller, with Vision Pro. Movement follows the direction you are looking.

| Input | Action |
| --- | --- |
| Left thumbstick | Move |
| Right thumbstick | Turn |
| Left / right trigger | Move down / up |
| D-pad up | Land on a model surface |
| D-pad right | Toggle terrain follow |
| D-pad left | Toggle faster movement |
| A | Show or dismiss saved locations |
| X / Y | Jump to the previous / next saved location |
| Look at the model and tap | Show or dismiss saved locations |
| Look at the model and double tap | Jump to the next saved location |

Press A to open the saved-locations panel. Movement pauses while it is visible, giving you a steady view as you add the current position or choose somewhere to revisit. Press A again to dismiss it, or use look and tap.

The controller guide appears below your view and adapts to the connected controller's own labels and glyphs. Both panels stay where they first appear in the immersive world instead of following your head.

You can also tap your thumb and middle finger together and hold for half a second, using either hand, to hide or reveal the model.

## Project notes

- [Prospector package format](Documentation/Prospector-Packages.md)
- [Performance review and Vision Pro profiling plan](PERFORMANCE.md)
- [Product and hardware follow-ups](TODO.md)

## Credits

The environment skybox is the [Meadow 2](https://polyhaven.com/a/meadow_2) HDRI from Poly Haven (CC0).
