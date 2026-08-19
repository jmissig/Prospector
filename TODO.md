# TODO

This is the product and engineering backlog for Prospector. Performance-specific investigations remain in [PERFORMANCE.md](PERFORMANCE.md).

## Vision Pro v1.1 findings

These items were observed on Vision Pro hardware after loading a real `.prospector` package. Treat the suspected causes as open questions until they are reproduced and instrumented.

### Decide what happens to the launch window during immersion

- The launch window containing **Enter Immersive View**, model selection, and resume controls remains visible while the immersive space is active.
- Moving the window out of the way is an acceptable v1.1 workaround, but the intended long-term window behavior is unsettled.
- Explore standard visionOS behavior for dismissing, hiding, minimizing, or repurposing the window while immersed, including how the user reliably gets it back.
- Preserve access to model switching, resume preferences, loading errors, and immersive-space exit rather than removing the window without a replacement path.

### Restore access to saved-locations controls

- Neither the immersive single-tap gesture nor controller **A** made the saved-locations panel or controller guide appear during the first v1.1 hardware test.
- Reproduce look-and-pinch and controller activation independently to determine whether the failure is input recognition, shared presentation state, RealityView attachment creation, or head-anchored placement/visibility.
- Add temporary diagnostics that distinguish “toggle action received” from “attachment rendered.”
- Verify the locations panel appears to the left and the independent controller guide appears bottom-center, then confirm dismiss, Add, jump, and delete on Vision Pro.

### Correct D-pad Up surface landing height

- D-pad **Up** leaves the viewer at least approximately one meter above the intended collision surface on hardware.
- Measure the raycast hit position, current viewer/model transform, device-anchor height, and applied `currentHeight` adjustment in a known location.
- Determine whether the offset comes from the Vision Pro world/floor coordinate frame, head-height handling, model transforms, the chosen collision hit, or another fixed offset.
- Do not compensate with an unexplained constant until the coordinate-space mismatch or collision-selection behavior is identified.
- Re-test on more than one model surface so a fix does not merely tune one location.

## Immersion modes

### Tune progressive immersion on Vision Pro

- Prospector now uses visionOS progressive immersion with a supported range of `0.2...1.0`, an initial amount of `0.6`, and a landscape portal. The Digital Crown controls the amount through standard system behavior.
- Verify on Vision Pro that locomotion, controller input, hand tracking, terrain follow, saved-location panels, and model scale remain correct at partial and full immersion.
- Determine how the surrounding passthrough boundary affects large architectural/site models and whether movement near that boundary is comfortable and understandable.
- Tune the minimum and initial amounts from hardware experience rather than Simulator appearance.
- Decide whether the system-restored immersion amount is sufficient or Prospector should remember an explicit user preference independently of model pose.
