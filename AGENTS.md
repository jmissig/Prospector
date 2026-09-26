# AGENTS.md

This file gives coding agents the durable context needed to work safely and consistently in this repository.

## Project posture

Current posture: **fork**.

This repository is Julian's Prospector fork, based on Christian Selig's upstream project at `christianselig/Prospector`. Make the smallest coherent change needed for the task. Do not add dependencies, requirements, or broad redesigns unless explicitly requested.

Preserve upstream compatibility where it makes future merges easier, but optimize for the real household use case rather than every possible upstream workflow. Keep local changes easy to identify and rebase.

## Project brief

Prospector is an Apple Vision Pro viewer for walking through authored-scale house and terrain models in immersive space. Private models are supplied at runtime in local `.prospector` document packages and must remain outside this public repository.

The household use case is:

- load house/site USDZ exports on Vision Pro;
- choose among multiple design options, initially Designs 01, 02, and 03;
- switch models without losing Prospector's useful navigation behavior;
- inspect designs at authored scale using a game controller, head-relative movement, vertical movement, terrain follow, and visibility controls.

The immediate product slice is **model selection and switching**. Saved starting positions, placement controls, and passthrough/full-immersion choices are plausible follow-on work, but should not be pulled into a task unless requested.

Source-of-truth boundaries:

- The authored USDZ exports are the source of truth for house and terrain geometry, scale, orientation, and design content.
- Copies bundled into the app or supplied in a `.prospector` package are runtime assets, not a new modeling source of truth.
- Do not silently rescale, rotate, simplify, or rewrite model geometry to compensate for viewer behavior.
- Keep model identity and display labels explicit in code rather than deriving product meaning from fragile filenames.

Non-goals:

- a general-purpose CAD, BIM, or USD editor;
- a model conversion or geometry-repair pipeline;
- a generic asset-management platform;
- a broad rewrite of upstream Prospector.

## Current state

Prospector is a small SwiftUI and RealityKit visionOS app targeting visionOS 26.2 or later.

- `Prospector/ContentView.swift` owns the small launch window.
- `Prospector/ImmersiveView.swift` loads one selected bundled or package-hosted model, preferring an optional compiled `.reality` hierarchy and falling back to USDZ plus runtime collisions. It owns immersive scene movement, collision probing, terrain follow, hand tracking, and mode cues.
- `Prospector/GameControllerManager.swift` maps controller input.
- The immersive RealityView must retain `.handlesGameControllerEvents(matching: .gamepad)`. Without it, visionOS can translate gamepad actions into model taps instead of delivering navigation input; adding it resolved the reported headset stall in 1.6.3.
- `Prospector/ProspectorApp.swift` declares the window and immersive space.
- `Prospector/ModelCatalog.swift` owns model selection and supports bundled and external file sources. It also retains app-session yaw across model switches and immersive-view recreation; only the first loaded model seeds yaw from its persisted/authored pose. Positions remain per-model, and explicit starting-position reset can change yaw.
- `Prospector/ProspectorDocument.swift` validates versioned `.prospector` package manifests and retains security-scoped access to their USDZ files.
- `Prospector/PositionPersistence.swift` reads and writes per-model `.state.json` pose/location sidecars and owns the coalesced write cadence.
- `Prospector/LandscapeEnvironment.swift` supports only explicit equirectangular panoramas; absent projection (including legacy landmark manifests) uses original Meadow. Preserve linear latitude, documented azimuth sign, loaded-dimension reporting and visual-only navigation semantics. `Tools/PanoramaChecks/run.sh` validates synthetic 4K/8K images on Mac; headset verification is separate.
- `Prospector/TerrainConfiguration.swift` validates optional shared terrain assets and per-model placement; `TerrainLayer.swift` owns serialized, cancellable visual-only loading and compatible reuse. Terrain never participates in house bounds, input, collisions, or persistence.
- The repository has no third-party package dependencies or Xcode test target. `Tools/TerrainChecks/run.sh` runs focused package/placement/lifecycle checks plus a synthetic USDZ import on macOS; it does not replace Vision Pro validation.

Preserve existing controller behavior unless the task explicitly changes it:

- left stick: movement relative to viewing direction;
- right stick: yaw;
- triggers: vertical movement;
- D-pad up: reset height to terrain;
- D-pad right: toggle terrain follow;
- D-pad left: toggle speed mode;
- thumb-to-middle-finger hold: toggle model visibility.

## Implementation guidance

- Saved locations restore direct navigation coordinates and preserve session yaw. Do not collision-probe on jumps or introduce shared per-model height offsets. Initial and manual landing adjust only the current position; saving records that position directly. Existing sidecars are not automatically migrated.

- Floor-coordinate evidence (Apple docs checked 2026-09-26): an ordinary ImmersiveSpace initially has its origin on the ground beneath the user ([WWDC24](https://developer.apple.com/videos/play/wwdc2024/10153/)); ARKit's queried device transform is in that immersive-space coordinate system ([WWDC24 device tracking](https://developer.apple.com/videos/play/wwdc2024/10093/?time=835)). Treat floor Y=0 as the intended initial reference, not an unsupported assumption requiring custom floor detection. Sitting/standing changes the tracked viewpoint, not the saved destination floor. Origin changes/recentering and coordinate conversions remain relevant; do not diagnose a seated floor-penetration report as a physical-floor-origin failure without evidence.

- Prefer a small explicit model descriptor/value type over a framework, registry service, or asset database.
- Keep model selection as plain Swift state and keep RealityKit entities at the immersive-view boundary.
- Make entity replacement lifecycle-safe: avoid duplicate scene entities, subscriptions, tracking sessions, and orphaned tasks.
- Preserve locomotion, collision generation, terrain probing, visibility state, and mode cues across the multi-model change unless a deliberate reset is part of the requested behavior.
- When diagnosing controller stalls, distinguish raw Game Controller callbacks from model tap gestures before treating A as proof of input delivery. Measure frame progress before replacing the update clock; keep behavioral experiments separate so a passing build is not mistaken for a confirmed runtime fix.
- Treat model-specific starting positions or placement adjustments as explicit per-model data when they are introduced; do not scatter filename checks through view code.
- Surface asset-loading failures clearly. Do not add new force unwraps or `try!` calls for user-selected models.
- Keep `.prospector` paths relative and contained within the package. Source models remain USDZ; optional compiled derivatives must be `.reality`. Do not weaken path or symlink validation.
- Retain security-scoped package access for as long as any of its model URLs can be loaded, and balance every successful access call.
- Keep transient poses and position-only named locations in each model's state sidecar, and authored defaults in the manifest model's optional `startPose`; never promote one into the other silently.
- Keep model switching understandable from the launch window before adding custom immersive controls.
- Prefer standard SwiftUI and visionOS controls (`Picker`, `Button`, `Form`, `Section`, ornaments where appropriate) and platform behavior before custom control chrome or fixed geometry.
- Use semantic text styles and accessible labels. Keep custom UI narrow and justified by an actual immersive interaction need.
- Follow existing Swift and RealityKit patterns unless a current Apple API materially simplifies the requested change.

## Validation

Routine checks:

```sh
xcodebuild -project Prospector.xcodeproj -list
xcodebuild -project Prospector.xcodeproj -scheme Prospector -sdk xrsimulator -destination 'generic/platform=visionOS Simulator' build
git diff --check
```

For model or immersive-behavior changes, a successful build is necessary but not sufficient. When the required assets and hardware/simulator capability are available, verify:

- every configured model is present in the app bundle and loads successfully;
- switching removes or disables the prior model and shows exactly one selected model;
- authored scale and orientation are preserved;
- controller movement, terrain follow, height reset, speed mode, and visibility toggling still work;
- leaving and re-entering immersive space does not duplicate content or input/update handling.

If Vision Pro-only behavior cannot be exercised, say exactly what was not verified.

Do not during routine verification:

- alter the authored source models;
- add or regenerate large USDZ assets without confirming the intended variants;
- change signing, team, bundle identity, or deployment settings merely to make a local build convenient;
- install, archive, publish, or deploy unless explicitly asked.

## Fork and git hygiene

- `origin` is Julian's fork: `jmissig/Prospector`.
- Canonical upstream is `christianselig/Prospector`.
- Do not repoint `origin` to upstream.
- If an `upstream` remote is needed, add it explicitly and keep fork work on branches based on the intended upstream/fork revision.
- Before reconciling upstream changes, inspect both histories and keep household-specific changes as small, legible commits.
- Do not opportunistically reformat or modernize unrelated upstream code.
- Do not add AI-generated footers or co-author lines to commits or pull requests.

## Documentation and working style

- Read this file and `README.md` before changing code.
- Keep `README.md` human-facing: setup, supported models, controls, and normal usage.
- Keep durable contributor constraints and architecture guidance here.
- When model configuration or controls change, update the code and the relevant README instructions together.
- Check the current diff before editing and preserve unrelated user changes.
- Ask only when a product choice would materially change behavior, model scope, or authored placement. Otherwise choose the narrowest implementation that advances the requested slice.

Build the small viewer that makes comparing the house designs easy. Do not build an empire.
