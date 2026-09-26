# Controller movement stall investigation

## Resolution

Julian reported on 2026-09-26 at 09:42 PDT that 1.6.3 appears to fix the
controller movement problem on Vision Pro. The fix is the immersive view's
`.handlesGameControllerEvents(matching: .gamepad)` declaration, not a scheduling
or terrain change. At his request, temporary navigation/terrain diagnostic
events, per-frame counters, and the package log writer have been removed.
Existing logs inside packages are left untouched; subsequent builds no longer
append to them. The sections below are historical evidence, including the
diagnostic instructions for 1.6.2/1.6.3, not current logging behavior.

## Headset evidence: 2026-09-26, 09:16–09:17 PDT

The returned package contains a complete 22-entry session from app 1.6.2,
build 16, running visionOS 27.0 (24M362), ending in immersive teardown.

- Terrain decoded and attached in approximately 0.069 seconds.
- Between two panel events 28.008 seconds apart, frame count advanced from
  909 to 3430: approximately 90 updates/second. The callback was not stalled.
- Every recorded panel toggle was `model tap`; there were no `controller A
  callback` or `controller A observed` entries. In conjunction with the user's
  report of using the controller, this supports system-translated tap routing.
- Navigation correctly changed back to enabled after each dismissal. Input
  event count nevertheless remained zero through frame 3676.
- At 09:17:10, four input callbacks arrived: right trigger press/release, then
  left trigger press/release. Their active intervals were approximately 0.165
  and 0.060 seconds. Transform count subsequently rose from 1 to 21, matching
  the user's brief up/down movement. No stick input appears in this capture.
- At teardown, 4259 frames had completed and navigation remained enabled.

This identifies input delivery as the failing stage for this reproduction,
not a stopped scene callback or stuck panel pause. The isolated correction
adds `.handlesGameControllerEvents(matching: .gamepad)` to the immersive
RealityView, as required by Apple's controller documentation. Scheduling,
terrain, input mappings, and diagnostic logging are unchanged. Hardware
verification of that correction remains pending. The capture does not establish
why the older omission became visible now; changed OS/focus behavior remains
unproven, and the last-known-good version/OS combination is still unknown.

The sections below preserve the pre-capture investigation and hypotheses.

## Report and confidence

Reported on 2026-09-26 against 1.6.1: sticks and ZL/ZR move briefly after
dismissing saved locations, then stop. A still opens/closes the panel and
physical head tracking continues. The last reliably working version/package
is not yet established. No headset trace or local reproduction is available.

**Root cause is not confirmed.** The earlier render-scheduled system patch was
premature and is set aside locally under `.build/navigation-stall-investigation`.
The working implementation retains the original `SceneEvents.Update` clock.

## What actually changed

- `d950b2e` (2026-08-19): stopped assigning the model transform and querying the
  device pose on stationary frames. This could matter to a scene-idling theory,
  but predates 1.5.2. During nonzero movement, transforms are still assigned
  on every received update; the optimization alone does not explain stopping
  in the middle of sustained input.
- `8fbffc7` and `643f0d9` (2026-08-20): made house meshes indirect input targets
  and added model single/double-tap gestures. A single tap opens/closes the
  same panel as the controller's A callback. Both changes are already in 1.5.2.
- `3b3d4ce` (1.6, 2026-09-25): added an optional panorama, disabled the Meadow
  entity when it is present, and transformed the panorama alongside the house.
  It does not change controller handlers or the navigation pause flag.
- `356e87d` (1.6.1, 2026-09-25): starts optional terrain loading after the house
  becomes usable, adds the loaded terrain under the content root, and assigns
  its transform alongside the house. It strips collision, input-target, and
  physics components before insertion. There is no terrain boundary/clamping
  check in locomotion and no terrain write to the controller's pause flag.
- `GameControllerManager.swift` is byte-for-byte identical between 1.5.2 and
  1.6.1. `SceneEvents.Update` and the panel pause/unpause path also predate these
  two releases. A recent regression can still expose older defects, but these
  are not newly introduced input or timer changes.

## Competing explanations

### Missing gamepad event routing: concrete omission, causation unconfirmed

Neither the immersive view nor another view declares
`.handlesGameControllerEvents(matching: .gamepad)`. Apple's
[visionOS 2 release notes](https://developer.apple.com/documentation/visionos-release-notes/visionos-2-release-notes)
require it for views using Game Controller. Apple's
[controller discovery guide](https://developer.apple.com/documentation/gamecontroller/discovering-game-controllers)
explains that visionOS otherwise converts gamepad actions into gaze-directed
pinch/UI events.

Consequently, A opening the panel is ambiguous: it could be a controller
callback **or** a translated tap reaching the model gesture. The latter does
not establish that analog input still reaches Game Controller. This omission
predates the recent releases. New scenery changes what a person looks at and
could expose an existing input-routing issue, but that link and the brief
post-dismissal grace period have not been measured. Do not present either as
established behavior.

### Frame updates stop: fits part of the report, not yet observed

Sticks, yaw, and triggers all consume cached inputs in the scene callback;
panel gestures/callbacks do not depend on it. That makes a stopped update clock
compatible with the report. However, Apple documents
[`SceneEvents.Update`](https://developer.apple.com/documentation/realitykit/sceneevents/update)
as a per-frame event and shows it as a supported update mechanism. We have no
trace showing that this subscription stops, nor proof that switching to a
`System` corrects this regression. A successful build is not runtime evidence.

### Terrain work stalls the app: new code path, weaker symptom match

Terrain decode, interaction stripping, insertion, and rendering are new costs;
visual-only does not mean performance-free. Delayed insertion could explain a
failure a few seconds after house load. Repeated temporary recovery on panel
dismissal is less directly explained by that one-time work. The currently
inspected terrain file is about 0.46 MiB; the prior package validation counted
37,762 triangles. File size is not a GPU or frame-time measurement. Head
tracking alone cannot rule out app stalls; responsive panel handling makes a
permanent main-actor blockage less likely.

### Panel pause or floor following: limited fit

Only `setLocationsPanelPresented` writes `navigationEnabled`, synchronously
to the inverse of the panel state. No delayed terrain task changes it.
A later unintended tap could still reopen/pause the panel, so log the source.
Terrain following changes height only; trigger-only and yaw movement do not
require a successful device-pose query or floor hit. A floor/collision failure
alone does not explain all three movement modes stopping.

## Diagnostic build (no scheduling or input-routing changes)

The open package receives `navigation-diagnostics.jsonl` automatically. Share
the package back after reproducing the stall (press A while stuck, then leave
immersion normally to let queued writes finish). Entries include UTC timestamps,
monotonic uptime, a package-open session UUID and sequence, and app/build/OS
metadata. Appends are serialized off the main actor with file coordination and
retain the package's security scope. The file is capped at 1 MiB, preserving
complete recent entries when compacted. Saved state and source assets are not
changed. Read-only/failed writes stop logging and surface a persistence warning;
navigation continues. Abrupt process termination can lose queued entries.

Unified logs use subsystem `Prospector`, category `Navigation`:

- `Controller A callback`: proves Game Controller delivered A, with cached
  and current framework stick/trigger state, navigation gate, and a count of
  continuous-input callbacks.
- `controller A observed` versus `model tap`: identifies which panel path ran.
- `panel will open/close`: logs the **pre-transition** pause/panel state,
  cumulative entered/completed frames, age of the last frame, and transform
  application count. Initial frame age `-1` means no frame has arrived yet.
- `analog input active/neutral`: transitions across a 0.1 diagnostic threshold,
  using current framework values; cached values in this entry are from just
  before the handler applies this event. This does not change movement dead zones.
- `navigation gate`: explicit pause/unpause changes.
- `terrain`: requested/absent/reused, decode start/completion, attachment timing,
  cancellation or failure. This distinguishes delayed asset insertion from input
  or frame delivery loss. `immersive teardown` records the final frame snapshot.

Counters are not observed by SwiftUI. Logging happens only on input, panel and
lifecycle events; there is no polling timer or animated diagnostics overlay that could
keep the scene awake and mask an idle-related failure. Positions, model names,
and package paths are not logged.

Reproduce with the original package. Once stuck, keep a stick displaced and
press A, then release it, dismiss, and repeat. Return the package or capture the logs in Xcode:

- Old last-frame age, stopped frame counts, enabled navigation and nonzero
  cached input support a scheduling failure. A freshly awakened frame just
  before the log can obscure the age, so compare consecutive snapshots too.
- Advancing frame counts but absent analog callbacks/framework state support
  input delivery loss. An unchanged input-event count while holding a stick
  perfectly steady is normal; release/reapply it to test event delivery.
- `model tap` without a controller A callback shows why A was misleading.
- Navigation disabled while the panel is closed indicates a gate/state bug.
- Advancing frames/transforms with a visually stationary house require checking
  rendering/entity state rather than replacing the input clock.

Then change one variable at a time: gamepad-routing modifier alone; terrain
disabled in a copy of the package; Meadow override with the same house. Do not
combine those with a scheduling rewrite. No source assets or packages were
modified during this investigation.
