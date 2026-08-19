# TODO

This is the product and engineering backlog for Prospector. Performance-specific work remains in [PERFORMANCE.md](PERFORMANCE.md).

## Saved locations and immersive controls

### Add deliberate saved-location editing

- Add an **Edit** button while keeping the normal saved-locations panel jump-only and safe from accidental destructive actions.
- In Edit mode, allow renaming and deleting saved locations with standard SwiftUI controls and clear confirmation before deletion.
- Persist edits to the active model's `.state.json` sidecar without changing location IDs, coordinates, timestamps, or other models' state.
- Verify cancellation, empty and duplicate names, read-only packages, iCloud write failures, and look-and-pinch interaction on Vision Pro.

### Decide whether the immersive panels should become system windows

- The locations panel and controller guide are world-stable RealityView attachments with native visionOS glass, but they do not receive system window bars, relocation, scaling, or close behavior.
- If they still feel foreign after hardware tuning, prototype auxiliary `WindowGroup` scenes and compare their system-managed behavior with the current deliberate left and bottom-center placement.

## Navigation

### Harden height reset and terrain follow

- Make D-pad **Up** edge-triggered so one press produces one reset instead of being processed on several scene-update frames.
- Preserve the current height when no upward-facing collision surface is found instead of falling back to zero.
- Verify terrain follow across flat ground, slopes, stairs, and overhangs. The corrected Z-up/model-space transforms and D-pad reset already work in Vision Pro testing.

## Immersion and window lifecycle

### Decide what happens to the launch window during immersion

- The launch window remains visible while immersive space is active; moving it aside is acceptable for now.
- Explore standard visionOS behavior for dismissing, hiding, minimizing, or repurposing it while preserving model switching, loading errors, immersive exit, and a reliable way to restore the window.

### Tune progressive immersion on Vision Pro

- Progressive immersion and Digital Crown control work on hardware with the current `0.2...1.0` range and `0.6` initial amount.
- Tune the minimum and initial amount based on comfort and the peripheral boundary around large architectural models.
- Test whether exiting, facing the launch window, and re-entering establishes a useful portal orientation; visionOS does not expose an API to bind the portal to the window.
- Decide whether system-restored immersion is sufficient or Prospector should remember a preference.
