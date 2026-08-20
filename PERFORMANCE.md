# Performance review

This is Prospector's active performance backlog. Validate optimizations with representative architectural USDZs on Apple Vision Pro and preserve the authored model geometry and current all-mesh collision behavior unless a separate product decision changes that requirement.

The `.prospector` document path is not an obvious bottleneck: manifest decoding runs away from the main actor, package access uses standard Foundation coordination and security scopes, and RealityKit loads model URLs asynchronously. The likely costs begin when RealityKit loads, preprocesses, collides, and renders a model.

## Active investigations

### Measure precompiled collision models on Vision Pro

Prospector supports optional Mac-precompiled `.reality` models and falls back to the source USDZ plus runtime collision generation. A representative proof preserved all 231 collision components and loaded the compiled hierarchy in about 0.14 seconds on the Mac, versus about 1.34 seconds to load the USDZ plus 4.52 seconds to generate collisions. The compiled file grew from 31 MB to 74 MB.

- Compare compiled and fallback loading time and peak memory on Vision Pro.
- Verify Land on Surface and terrain-follow behavior against the same source model through both paths.
- Decide whether future tooling should record a source fingerprint; the current authoring contract requires regeneration whenever the source USDZ changes.

Relevant code: `Prospector/ImmersiveView.swift`, `Prospector/ProspectorDocument.swift`, and `Tools/ProspectorCollisionCompiler/main.swift`.

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
