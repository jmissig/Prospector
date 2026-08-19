# Performance review

This is Prospector's active performance backlog. Validate optimizations with representative architectural USDZs on Apple Vision Pro and preserve the authored model geometry and current all-mesh collision behavior unless a separate product decision changes that requirement.

The `.prospector` document path is not an obvious bottleneck: manifest decoding runs away from the main actor, package access uses standard Foundation coordination and security scopes, and RealityKit loads model URLs asynchronously. The likely costs begin when RealityKit loads, preprocesses, collides, and renders a model.

## Active investigations

### Preprocess exact collision meshes on the Mac

Prospector currently walks every `ModelEntity` and calls `ShapeResource.generateStaticMesh(from:)`. Vision Pro testing confirms model loading is noticeable but completes in less than a minute; USDZ decoding and collision-generation time have not yet been measured separately.

- Profile USDZ loading and collision generation independently.
- Prototype a Mac-side tool that performs the same exact all-mesh collision generation once and exports a compiled RealityKit entity hierarchy beside the USDZ in the `.prospector` package.
- Verify that the compiled artifact preserves visuals, hierarchy, transforms, collisions, and raycast behavior on visionOS.
- Record a source-model fingerprint and generator version so stale output is never mistaken for current geometry.
- Compare preprocessing time, package size, Vision Pro load time, and peak memory with the current path.

Relevant code: `Prospector/ImmersiveView.swift`, `loadModel` and `generateStaticMeshCollisionShapes`.

### Measure controller-driven SwiftUI invalidation

Navigation position, yaw, and height already live in a non-observed runtime object, and stationary frames avoid device-pose queries and model-transform assignments. Continuous controller axes are still `@Published` by `GameControllerManager`, so they may invalidate SwiftUI while moving.

- Use SwiftUI Instruments to measure body updates during sustained stick and trigger input.
- If measurable, keep continuous axes in a non-observed runtime store and publish only discrete UI state such as controller identity and mode changes.

Relevant code: `Prospector/GameControllerManager.swift` and the `SceneEvents.Update` handler in `Prospector/ImmersiveView.swift`.

### Profile authored model and rendering cost

Rendering cost still depends on entity and mesh-part counts, triangles, materials, texture sizes, transparency/overdraw, collider complexity, and the bundled 4096×2048 environment texture.

- Capture draw calls, triangles, GPU time, dropped frames, RealityKit Physics CPU, and steady-state memory while walking representative models.
- Measure terrain-follow raycasts during continuous movement; throttle by elapsed time or distance only if they are a demonstrated cost.
- Treat asset-side changes as an explicit export decision and leave authoritative private source models untouched.

## Current baseline

- Only one app-owned model is retained or loaded at a time; replacement work is serialized and stale requests are canceled.
- ARKit startup, hand updates, scene subscriptions, and teardown have explicit task ownership and call `ARKitSession.stop()` on exit.
- Navigation-space bounds are cached at load time, and stationary scene updates skip unnecessary device-pose and transform work.
- Z-up USDZ collision probing correctly transforms ray endpoints, hit positions, normals, bounds, scale, and the viewer's physical X/Z position.
- Manifest decoding, asynchronous RealityKit loading, and retained package security scope have no observed ongoing performance problem.

## Profiling pass

On Vision Pro, exercise:

1. Open a package and load its default model.
2. Walk continuously with terrain follow enabled across elevation changes.
3. Switch repeatedly between the two largest models, then exit and re-enter immersive space.

Capture:

- USDZ load and collision-preprocessing duration;
- peak and steady-state memory;
- Entity Commits and SwiftUI body updates;
- RealityKit Physics CPU time;
- draw calls, triangles, GPU time, and dropped frames;
- retained ARKit providers, tasks, or subscriptions after immersive exit.

Use RealityKit Trace, Time Profiler, and SwiftUI Instruments. Optimize the largest measured cost first and repeat the same capture after each change.
