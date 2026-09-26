# TODO

This is the product and engineering backlog for Prospector. Performance-specific work remains in [PERFORMANCE.md](PERFORMANCE.md).

## Surrounding terrain

- The optional shared terrain contract and visual-only asynchronous layer are implemented. Follow the [terrain plan](Documentation/Terrain-Plan.md) for the remaining aligned-asset and headset validation.
- Keep the detailed site authoritative and verify the coarse-terrain transition and finite panorama shell together.
- Defer optional walkable-terrain collisions until alignment and performance are established; no streaming/GIS runtime or new settings UI in the first increment.

## Saved locations and immersive controls

### Verify direct tap navigation on Vision Pro

- Verify that a single indirect tap on the model opens and dismisses the saved-locations panel.
- Verify that a double tap jumps to the next saved location without also toggling the panel.
- Confirm that model-target gestures do not interfere with look-and-tap interaction inside the visible panel.

### Add deliberate saved-location editing

- Add an **Edit** button while keeping the normal saved-locations panel jump-only and safe from accidental destructive actions.
- In Edit mode, allow renaming and deleting saved locations with standard SwiftUI controls and clear confirmation before deletion.
- Persist edits to the active model's `.state.json` sidecar without changing location IDs, coordinates, timestamps, or other models' state.
- Verify cancellation, empty and duplicate names, read-only packages, iCloud write failures, and look-and-pinch interaction on Vision Pro.

### Decide whether the immersive panels should become system windows

- The locations panel and controller guide are world-stable RealityView attachments with native visionOS glass, but they do not receive system window bars, relocation, scaling, or close behavior.
- If they still feel foreign after hardware tuning, prototype auxiliary `WindowGroup` scenes and compare their system-managed behavior with the current deliberate left and bottom-center placement.

## Navigation

### Diagnose intermittent controller movement stalls

- 1.6.1 report: movement stops shortly after dismissing saved locations, while A and head tracking continue. Root cause is not confirmed.
- See [investigation and diagnostic log interpretation](Documentation/Navigation-Stall-Investigation.md). Keep baseline frame scheduling while identifying raw controller callbacks versus translated tap gestures and measuring frame/update progress.

### Verify session floor calibration

- Prospector attempts **Land on Surface** once after a model first loads, then recalibrates the shared per-model session offset at each saved-location jump.
- Manual **Land on Surface** adjusts only the current runtime height; it must not alter the shared offset used by later jumps.
- Verify repeated jumps remain close to their intended heights without changing stored JSON coordinates, including after manually landing while freely exploring.
- Verify automatic calibration, model switching, flat ground, upper floors, slopes, stairs, overhangs, and locations where no upward-facing surface is found.

## Immersion and window lifecycle

### Decide what happens to the launch window during immersion

- The launch window remains visible while immersive space is active; moving it aside is acceptable for now.
- Prospector starts windowed, dismisses immersion when the launch window disappears or the app backgrounds, and synchronizes the button from the immersive scene's actual appearance/disappearance. Verify fresh launch, closing the window, and switching apps on Vision Pro, including transitions while an open request is still pending.
- Explore standard visionOS behavior for dismissing, hiding, minimizing, or repurposing it while preserving model switching, loading errors, immersive exit, and a reliable way to restore the window.

### Tune progressive immersion on Vision Pro

- Progressive immersion and Digital Crown control work on hardware with the current `0.2...1.0` range and `0.6` initial amount.
- Tune the minimum and initial amount based on comfort and the peripheral boundary around large architectural models.
- Test whether exiting, facing the launch window, and re-entering establishes a useful portal orientation; visionOS does not expose an API to bind the portal to the window.
- Decide whether system-restored immersion is sufficient or Prospector should remember a preference.
