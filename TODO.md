# TODO

This is the product and engineering backlog for Prospector. Performance-specific investigations remain in [PERFORMANCE.md](PERFORMANCE.md).

## Navigation persistence

### Continuously store the current position within each model

- Track the viewer's current position, yaw, and any other pose state required to resume the same viewpoint.
- Persist pose updates periodically and when leaving immersive space, switching models, opening another package, or moving the app to the background.
- Scope stored state to a stable package and model identity so models with the same manifest ID do not share positions accidentally.
- Restore a model's most recent pose when returning to it, while providing a deliberate way to reset to its authored/default starting position.
- Keep coordinates in the model's authored coordinate space; do not modify or normalize the USDZ to implement persistence.
- Avoid writing on every rendered frame. Coalesce or debounce updates and use a final lifecycle save where possible.

### Save and jump to named positions

- Let the user save the current pose as a named position for the active model.
- Present saved positions for the current model and allow one-step jumping to a selected position.
- Support renaming and deleting saved positions with clear confirmation for destructive actions.
- Decide whether named positions live only on the device or can be stored alongside/shareable with a `.prospector` package without requiring Prospector to rewrite the package unexpectedly.
- Define a versioned saved-position representation that can later include position, yaw, height/terrain-follow state, and an optional descriptive label.
- Handle model/package changes gracefully: never apply a saved pose to a different model merely because its display name matches.

## Immersion modes

### Investigate partial immersion support

- Confirm which visionOS immersive-space styles and progressive-immersion APIs are available at the deployment target (visionOS 26.2).
- Prototype whether Prospector can offer a useful partial/progressive immersion mode while retaining model scale, locomotion, controller input, hand tracking, and terrain-follow behavior.
- Determine how the surrounding passthrough boundary affects large architectural/site models and whether movement near that boundary is comfortable and understandable.
- Compare full, mixed/progressive, and passthrough-oriented experiences on Vision Pro rather than choosing from Simulator behavior alone.
- If viable, expose the choice through standard visionOS controls and remember the user's preference independently of model pose.
