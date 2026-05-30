# Trajectory Type - Agent Context

## Project
- Web-only Vite prototype for drawing camera-sampled strokes on a mobile browser.
- The camera feed is accessed with `getUserMedia`; strokes are driven by pointer/touch input.
- The output is a screen-space 2D canvas composition, not AR/world-space geometry.
- The current renderer uses Canvas 2D and offscreen canvases. WebGPU is not required for the baseline experience.

## Commands
- Install dependencies: `npm install`
- Run dev server: `npm run dev`
- Build: `npm run build`

## Conventions
- Keep the first screen as the usable camera drawing surface.
- Optimize for iOS Safari and mobile touch input.
- Use feature detection for optional browser APIs.
- Keep camera access behind a secure context; the Vite dev server uses HTTPS via the basic SSL plugin.

## Known Constraints
- iOS camera access requires HTTPS and user permission.
- WebGPU support depends on Safari/iOS version; do not make WebGPU mandatory without a Canvas fallback.
- Avoid native iOS/Xcode project work unless the project direction changes again.
