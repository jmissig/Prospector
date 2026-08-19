# AGENTS.md

This file gives coding agents the durable context needed to work safely and consistently in this repository.

## Project posture

Current posture: **fork**.

This repository is Julian's Prospector fork, based on Christian Selig's upstream project at `christianselig/Prospector`. Make the smallest coherent change needed for the task. Do not add dependencies, requirements, or broad redesigns unless explicitly requested.

Preserve upstream compatibility where it makes future merges easier, but optimize for the real household use case rather than every possible upstream workflow. Keep local changes easy to identify and rebase.

## Project brief

Prospector is an Apple Vision Pro viewer for walking through authored-scale house and terrain models in immersive space. Private models are supplied at runtime in local `.prospector` document packages and must remain outside this public repository.

The household use case is:

- load the 636 house/site USDZ exports on Vision Pro;
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
- `Prospector/ImmersiveView.swift` loads one selected bundled or package-hosted USDZ entity and owns immersive scene movement, collision probing, terrain follow, hand tracking, and mode cues.
- `Prospector/GameControllerManager.swift` maps controller input.
- `Prospector/ProspectorApp.swift` declares the window and immersive space.
- `Prospector/ModelCatalog.swift` owns model selection and supports bundled and external file sources.
- `Prospector/ProspectorDocument.swift` validates versioned `.prospector` package manifests and retains security-scoped access to their USDZ files.
- The repository currently has no third-party package dependencies or test target.

Preserve existing controller behavior unless the task explicitly changes it:

- left stick: movement relative to viewing direction;
- right stick: yaw;
- triggers: vertical movement;
- D-pad up: reset height to terrain;
- D-pad right: toggle terrain follow;
- D-pad left: toggle speed mode;
- thumb-to-middle-finger hold: toggle model visibility.

## Implementation guidance

- Prefer a small explicit model descriptor/value type over a framework, registry service, or asset database.
- Keep model selection as plain Swift state and keep RealityKit entities at the immersive-view boundary.
- Make entity replacement lifecycle-safe: avoid duplicate scene entities, subscriptions, tracking sessions, and orphaned tasks.
- Preserve locomotion, collision generation, terrain probing, visibility state, and mode cues across the multi-model change unless a deliberate reset is part of the requested behavior.
- Treat model-specific starting positions or placement adjustments as explicit per-model data when they are introduced; do not scatter filename checks through view code.
- Surface asset-loading failures clearly. Do not add new force unwraps or `try!` calls for user-selected models.
- Keep `.prospector` paths relative, contained within the package, and restricted to USDZ files. Do not weaken path or symlink validation.
- Retain security-scoped package access for as long as any of its model URLs can be loaded, and balance every successful access call.
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
