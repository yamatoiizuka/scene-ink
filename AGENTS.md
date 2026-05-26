# TrajectoryType - Agent Context

## Project
- iOS app that records camera trajectory in 3D space and renders it as calligraphy-like strokes.
- Swift 6, SwiftUI + UIKit bridge for ARKit views.
- ARKit `ARWorldTrackingConfiguration` for 6DoF pose tracking.
- Metal is planned for texture-mapped trajectory meshes in later milestones.
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
