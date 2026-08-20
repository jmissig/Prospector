# TODO

This is the product and engineering backlog for Prospector. Performance-specific work remains in [PERFORMANCE.md](PERFORMANCE.md).

## Saved locations and immersive controls

### Investigate pinch-to-show locations

- The intended single pinch/tap gesture does not show the saved-locations panel on Vision Pro; controller A remains the documented reliable entry point.
- Determine whether the immersive gesture is not being recognized, is attached to the wrong RealityKit target, or conflicts with system input handling.
- Verify opening and dismissal with direct hand input on Vision Pro without changing look-and-pinch interaction inside the visible panel.

### Add deliberate saved-location editing

- Add an **Edit** button while keeping the normal saved-locations panel jump-only and safe from accidental destructive actions.
- In Edit mode, allow renaming and deleting saved locations with standard SwiftUI controls and clear confirmation before deletion.
- Persist edits to the active model's `.state.json` sidecar without changing location IDs, coordinates, timestamps, or other models' state.
- Verify cancellation, empty and duplicate names, read-only packages, iCloud write failures, and look-and-pinch interaction on Vision Pro.

### Decide whether the immersive panels should become system windows

- The locations panel and controller guide are world-stable RealityView attachments with native visionOS glass, but they do not receive system window bars, relocation, scaling, or close behavior.
- If they still feel foreign after hardware tuning, prototype auxiliary `WindowGroup` scenes and compare their system-managed behavior with the current deliberate left and bottom-center placement.

## Navigation

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
