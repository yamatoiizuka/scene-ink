# TrajectoryType - Agent Context

## Project
- iOS app that records camera motion and camera frames, then stitches those frames into calligraphy-like strokes on the iPhone screen.
- The final stroke is a screen-space 2D composition, not a line or mesh left in AR world space.
- Swift 6, SwiftUI + UIKit bridge for ARKit views.
- ARKit `ARWorldTrackingConfiguration` provides 6DoF pose tracking and camera frames.
- Device translation maps to screen-space stroke movement; device rotation/roll should affect stroke curve, skew, and image-slice orientation.
- The current prototype may use CPU/CoreGraphics image patches first; Metal is planned for higher-quality texture-mapped screen-space stroke compositing in later milestones.
- Minimum deployment: iOS 17.0.

## MCP Tools
- Prefer XcodeBuildMCP for build, test, simulator, and device operations.
- Use Xcode's native MCP for project structure queries and diagnostics when available.
- Avoid raw `xcodebuild` commands when MCP tools can perform the same task.

## Conventions
- File naming: PascalCase, one type per file.
- SwiftUI views are suffixed with `View`.
- ARKit-related types are prefixed with `AR`.
- Metal shaders should live under `Shaders/`.
- Tests use the Swift Testing framework.

## Known Constraints
- ARKit does not provide full camera/world tracking behavior in Simulator. Device verification is required for AR behavior.
- Camera frame access comes from `ARSession.currentFrame?.capturedImage`.
- Render and capture loops should follow AR session updates rather than a separate display link.
- Do not implement AR-world stroke persistence unless explicitly requested; trajectory visualization should be screen-space.
