# TODO

This is the product and engineering backlog for Prospector. Performance-specific investigations remain in [PERFORMANCE.md](PERFORMANCE.md).

## Vision Pro v1.1 findings

These items were observed on Vision Pro hardware after loading a real `.prospector` package. Keep suspected causes distinct from measured ones.

### Decide what happens to the launch window during immersion

- The launch window containing **Enter Immersive View**, model selection, and resume controls remains visible while the immersive space is active.
- Moving the window out of the way is an acceptable v1.1 workaround, but the intended long-term window behavior is unsettled.
- Explore standard visionOS behavior for dismissing, hiding, minimizing, or repurposing the window while immersed, including how the user reliably gets it back.
- Preserve access to model switching, resume preferences, loading errors, and immersive-space exit rather than removing the window without a replacement path.

### Verify saved-locations controls and spatial placement

- Neither the immersive single-tap gesture nor controller **A** made the saved-locations panel or controller guide appear during the first v1.1 hardware test.
- A later hardware build displayed both panels, confirming the attachments render, but they were incorrectly parented to a head anchor and followed every head movement. The controller guide was also much taller than its content because an unconstrained vertical divider expanded the row, and the locations panel used a nonstandard text-and-symbol dismissal control.
- Prospector now samples the headset position and yaw once when the panels open, places both attachments in world space, constrains the controller guide to its ideal content height, and uses a standard icon-only Close button with an accessibility label.
- The attachments now use visionOS's native glass background effect and standard button styles. The controller guide groups shoulders, D-pad, sticks, and face buttons spatially instead of imitating a generic data table.
- RealityView attachments are not system windows: they don't receive a window bar, relocation controls, dynamic scale, or other window behavior. If the refined glass attachments still feel foreign on hardware, investigate presenting saved locations and the controller reference as auxiliary `WindowGroup` scenes, accepting that visionOS—not Prospector—would control their placement.
- Verify look-and-pinch and controller **A** independently open the panels in the current build.
- Verify the locations panel remains world-stable to the left and the independent controller guide remains world-stable at bottom-center, then confirm Close, Add, and jump on Vision Pro. Saved-location deletion is deliberately unavailable in the immersive panel after an accidental hardware-test deletion.

### Verify corrected D-pad Up and terrain-follow transforms

- The measured cause was a model/navigation coordinate-space mismatch: the three tested 636 USDZs are Z-up and RealityKit imports them with an approximately -90-degree root rotation, while the old probe incorrectly treated entity-local -Y as navigation down.
- Prospector now transforms ray endpoints, hit positions, normals, and bounds through the complete imported root transform. It also probes beneath the headset's physical X/Z displacement and chooses the upward-facing hit closest to the current navigation height.
- D-pad **Up** now lands correctly in hardware testing. A temporary release-build log captured 375 probe frames across Designs 02 and 03: device pose was available for every frame, 365 frames selected upward-facing collision surfaces, and selected heights varied with location. This validates the corrected coordinate transforms and rules out a fixed model-space ray column.
- Verify terrain follow across flat ground, slopes, stairs, and overhangs so the closest-height selection does not jump to another upward-facing surface.
- The same log exposed two follow-ups: each physical D-pad press was processed on roughly 5–10 scene-update frames, and one 10-frame request had no collision hit and applied the zero-height fallback. Make reset input edge-triggered and preserve the current height when no surface is found instead of silently jumping to zero.
- Release-build terrain-probe logging was removed after collecting this evidence. Existing `terrain-probe.jsonl` files are inert historical diagnostics and can be deleted manually when no longer useful.

## Immersion modes

### Tune progressive immersion on Vision Pro

- Prospector now uses visionOS progressive immersion with a supported range of `0.2...1.0`, an initial amount of `0.6`, and a landscape portal. The Digital Crown controls the amount through standard system behavior.
- Verify on Vision Pro that locomotion, controller input, hand tracking, terrain follow, saved-location panels, and model scale remain correct at partial and full immersion.
- Determine how the surrounding passthrough boundary affects large architectural/site models and whether movement near that boundary is comfortable and understandable.
- Tune the minimum and initial amounts from hardware experience rather than Simulator appearance.
- Decide whether the system-restored immersion amount is sufficient or Prospector should remember an explicit user preference independently of model pose.
