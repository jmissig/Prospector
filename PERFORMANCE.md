# Performance review

This note records the code-review findings from August 2026. It is a prioritized investigation backlog, not a claim that every item is a measured bottleneck. Validate changes with a representative architectural USDZ on Apple Vision Pro before optimizing broadly.

The `.prospector` document path itself is not an obvious performance concern. It uses standard Foundation file coordination and security-scoped access, decodes the small JSON manifest away from the main actor, and hands model URLs to RealityKit's asynchronous loading APIs. The likely costs begin when RealityKit loads, preprocesses, collides, and renders the model.

## Priority findings

### 1. High: exact collision generation may dominate loading

`ImmersiveView.generateStaticMeshCollisionShapes(for:)` walks the complete entity hierarchy and generates an exact static-mesh collision shape for every `ModelEntity`. Large architectural/site models can contain many meshes and substantial geometry, making this preprocessing expensive in both time and memory.

The first v1.1 Vision Pro test confirmed that loading a real design has a noticeable delay but completes in less than a minute. It was not obnoxious enough to be the most urgent usability issue, but remains worth improving. The test did not separate USDZ decoding from collision generation, so the exact share attributable to collision preprocessing is still unmeasured.

Collision traversal now checks cancellation before processing each entity and after asynchronous static-mesh generation. Model replacement also serializes load operations, so a newer request waits for the canceled request to finish cleanup before beginning another USDZ load. RealityKit's individual static-mesh operation may still take time to return after cancellation, so its cost remains a profiling target.

Recommended investigation:

- Profile collision preprocessing separately from USDZ decoding.
- Preserve the current behavior of generating exact static-mesh collisions for every `ModelEntity`; do not assume a terrain-only or simplified collision model.
- Prototype a Mac-side preprocessor that performs the same all-mesh collision generation once and exports a compiled RealityKit entity hierarchy beside the USDZ in the `.prospector` package.
- Measure whether loading that preprocessed artifact avoids the Vision Pro collision-generation delay while preserving collision and raycast behavior exactly.
- Record cache provenance or a source-model fingerprint so stale preprocessed output is not mistaken for current geometry.

Relevant code: `Prospector/ImmersiveView.swift`, `loadModel` and `generateStaticMeshCollisionShapes`.

### 2. Addressed: switching temporarily retained two complete models

Model replacement now records and flushes the outgoing pose, removes the active entity, and clears its retained model and rotation state before beginning replacement USDZ loading. The immersive environment is intentionally empty while the replacement loads, and a failed replacement leaves the old model unloaded rather than restoring its memory cost.

Replacement requests are serialized. Rapid A → B → C selection cancels obsolete work, waits for its cleanup, and allows only the current request to attach an entity.

Validation still required on Vision Pro:

- Compare peak resident memory while switching between the two largest representative models.
- Confirm the old entity disappears before replacement loading and that only the final model attaches after rapid selection changes.
- Confirm a failed replacement leaves the scene empty and presents the existing load error.

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
- creates and assigns an entity transform even when no movement, rotation, height, or visibility changed.

The model's navigation-space bounds are now computed once at load time and reused by terrain-follow and height-reset raycasts. This removes the former per-probe `visualBounds` calculation and also accounts for imported root rotation, translation, and scale.

Recommended investigation:

- Query head orientation only when horizontal movement needs it.
- Track whether pose state changed and assign the entity transform only when dirty.
- If terrain raycasts are measurable, throttle them by elapsed time or distance traveled while retaining acceptable ground following.

Relevant code: `Prospector/ImmersiveView.swift`, the `SceneEvents.Update` handler and `terrainSurfaceHeight`.

### 5. Addressed: ARKit startup and shutdown are explicitly controlled

World/hand tracking startup and hand-anchor consumption now use owned tasks. Startup checks cancellation after authorization and session startup. The shared immersive teardown path cancels startup and hand-update tasks, calls `ARKitSession.stop()`, clears provider references, resets pinch state, cancels RealityKit/model-loading work, and releases the current entity.

Validation still required on Vision Pro:

- Exit while authorization or session startup is pending and confirm no provider resumes afterward.
- Repeat enter/exit cycles and confirm one session, one hand-update consumer, and one RealityKit update subscription per immersive presentation.
- Confirm world-relative movement and hand visibility toggling still work after re-entry.

Relevant code: `Prospector/ImmersiveView.swift`, RealityView setup and `onDisappear`.

### 6. Trace-dependent: USDZ complexity may dominate rendering

RealityKit handles rendering, but performance still depends heavily on the authored asset: entity and mesh-part counts, triangle count, material count, texture sizes, transparency/overdraw, and collider complexity. The bundled `meadow_2_4k.exr` is about 22 MB on disk and should be included in memory measurements, although model structure and collision generation are the higher-priority suspects.

Do not silently rescale, simplify, or rewrite private source models as part of routine viewer optimization. If asset-side changes prove necessary, treat them as an explicit export/profile decision and preserve the authored source of truth.

## What already looks sound

- Manifest coordination and decoding do not run on the main actor.
- RealityKit model loading is asynchronous.
- At most one app-owned model entity is retained or loading at a time.
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
