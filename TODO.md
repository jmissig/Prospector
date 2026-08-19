# TODO

This is the product and engineering backlog for Prospector. Performance-specific investigations remain in [PERFORMANCE.md](PERFORMANCE.md).

## Immersion modes

### Investigate partial immersion support

- Confirm which visionOS immersive-space styles and progressive-immersion APIs are available at the deployment target (visionOS 26.2).
- Prototype whether Prospector can offer a useful partial/progressive immersion mode while retaining model scale, locomotion, controller input, hand tracking, and terrain-follow behavior.
- Determine how the surrounding passthrough boundary affects large architectural/site models and whether movement near that boundary is comfortable and understandable.
- Compare full, mixed/progressive, and passthrough-oriented experiences on Vision Pro rather than choosing from Simulator behavior alone.
- If viable, expose the choice through standard visionOS controls and remember the user's preference independently of model pose.
