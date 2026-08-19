# Performance review

This note records the code-review findings from August 2026. It is a prioritized investigation backlog, not a claim that every item is a measured bottleneck. Validate changes with a representative architectural USDZ on Apple Vision Pro before optimizing broadly.

The `.prospector` document path itself is not an obvious performance concern. It uses standard Foundation file coordination and security-scoped access, decodes the small JSON manifest away from the main actor, and hands model URLs to RealityKit's asynchronous loading APIs. The likely costs begin when RealityKit loads, preprocesses, collides, and renders the model.

## Priority findings

### 1. High: exact collision generation may dominate loading

`ImmersiveView.generateStaticMeshCollisionShapes(for:)` walks the complete entity hierarchy and generates an exact static-mesh collision shape for every `ModelEntity`. Large architectural/site models can contain many meshes and substantial geometry, making this preprocessing expensive in both time and memory.

The current load task checks cancellation only after the entire hierarchy has been processed. Selecting another model can therefore leave obsolete collision work running until traversal finishes.

Recommended investigation:

- Profile collision preprocessing separately from USDZ decoding.
- Prefer a simplified, terrain-only collision mesh or explicitly designated walkable entities when the source model can provide them.
- If full-hierarchy traversal remains necessary, check cancellation between entities and stop obsolete work promptly.
- Minimize collider complexity while preserving terrain-follow behavior.

Relevant code: `Prospector/ImmersiveView.swift`, `loadModel` and `generateStaticMeshCollisionShapes`.

### 2. High: switching temporarily retains two complete models

The active entity remains attached while the replacement USDZ loads and generates collision shapes. The prior entity is removed only when the replacement is ready. This provides seamless visual replacement, but peak memory can approach the combined model, texture, and collider cost of both models.

For large house/site models, that temporary overlap could cause memory pressure or process termination.

Recommended investigation:

- Measure peak resident memory while switching between the two largest representative models.
- If overlap is unsafe, remove and release the old model before loading the replacement, or at least before generating replacement collision shapes.
- Preserve a clear loading state if switching becomes intentionally non-atomic.

Relevant code: `Prospector/ImmersiveView.swift`, `loadModel`.

### 3. Medium-high: hot movement state may invalidate SwiftUI

Position, yaw, and height are SwiftUI `@State` values mutated from the RealityKit scene-update callback. Controller axes are `@Published` values on an `ObservableObject` and can change frequently. This may trigger unnecessary SwiftUI invalidation during continuous movement even though most of this data only drives RealityKit transforms.

Recommended investigation:

- Use SwiftUI Instruments to confirm whether controller input or per-frame movement causes frequent body updates.
- Move frame-hot runtime values into a non-observed reference object, RealityKit component/system, or another runtime store that does not invalidate the view.
- Keep only state that actually affects SwiftUI controls or overlays observable.

Relevant code: `Prospector/ImmersiveView.swift` state and scene-update subscription; `Prospector/GameControllerManager.swift` published inputs.

### 4. Medium: avoidable work occurs every scene update

The update callback currently:

- queries the device anchor for head orientation even when the player is stationary;
- creates and assigns an entity transform even when no movement, rotation, height, or visibility changed;
- recomputes `visualBounds` whenever terrain-follow or height reset performs a raycast.

Recommended investigation:

- Query head orientation only when horizontal movement needs it.
- Track whether pose state changed and assign the entity transform only when dirty.
- Cache the loaded model's bounds or the derived ray length until the model changes.
- If terrain raycasts are measurable, throttle them by elapsed time or distance traveled while retaining acceptable ground following.

Relevant code: `Prospector/ImmersiveView.swift`, the `SceneEvents.Update` handler and `terrainSurfaceHeight`.

### 5. Medium: ARKit startup and shutdown are not fully controlled

World/hand tracking starts in an unretained task. On disappearance, the hand-update task and RealityKit subscription are canceled, but the startup task is not retained or canceled and the `ARKitSession` is not explicitly stopped. A quick immersive-space exit could allow setup to complete after dismissal or keep providers alive longer than intended.

Recommended change:

- Retain the startup task and cancel it on disappearance.
- Explicitly stop the ARKit session when leaving immersive space.
- Verify repeated enter/exit cycles do not duplicate providers, update streams, or resource usage.

Relevant code: `Prospector/ImmersiveView.swift`, RealityView setup and `onDisappear`.

### 6. Trace-dependent: USDZ complexity may dominate rendering

RealityKit handles rendering, but performance still depends heavily on the authored asset: entity and mesh-part counts, triangle count, material count, texture sizes, transparency/overdraw, and collider complexity. The bundled `meadow_2_4k.exr` is about 22 MB on disk and should be included in memory measurements, although model structure and collision generation are the higher-priority suspects.

Do not silently rescale, simplify, or rewrite private source models as part of routine viewer optimization. If asset-side changes prove necessary, treat them as an explicit export/profile decision and preserve the authored source of truth.

## What already looks sound

- Manifest coordination and decoding do not run on the main actor.
- RealityKit model loading is asynchronous.
- After a completed switch, only the selected model remains attached.
- The launch-window picker has a small, stable data set and no expensive render-time transformations.
- Retaining security-scoped access for the active package has no obvious ongoing performance cost.

## Measurement plan

Run the first profiling pass on Apple Vision Pro with representative large models. Exercise three scenarios:

1. Open a package and load its default model.
2. Walk continuously with terrain follow enabled, including changes in elevation.
3. Switch repeatedly between the two largest models, then exit and re-enter immersive space.

Capture at least:

- model load duration, split where possible into USDZ load and collision preprocessing;
- peak and steady-state memory;
- Entity Commits and SwiftUI view updates;
- RealityKit Physics CPU time;
- draw calls, triangles, GPU time, and dropped frames;
- retained ARKit providers/tasks after immersive-space exit.

Use RealityKit Trace and SwiftUI Instruments. Optimize the largest measured cost first, then repeat the same capture to verify the change rather than relying on code-level intuition alone.
