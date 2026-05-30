import CoreGraphics
import Foundation
import Observation
@preconcurrency import ARKit

@MainActor
@Observable
public final class ARSessionManager: NSObject {
    public let session: ARSession
    public private(set) var latestPose: CameraPose?
    public private(set) var hasStrokeSourceImage = false
    public private(set) var trackingDescription = "AR session is not running."
    public private(set) var isRunning = false
    public var brushAngleRadians: CGFloat = 0
    public private(set) var normalizedBrushSamplePoint = CGPoint(x: 0.5, y: 0.5)
    public private(set) var brushPreviewSize: CGSize?
    private let frameCapture = FrameCapture()
    private var strokeSourceImage: CGImage?

    public override init() {
        self.session = ARSession()
        super.init()
        session.delegate = self
    }

    public func start() {
        guard ARWorldTrackingConfiguration.isSupported else {
            isRunning = false
            trackingDescription = "ARWorldTrackingConfiguration is not supported on this device."
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = []
        configuration.environmentTexturing = .none

        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
        trackingDescription = "Starting AR session..."
    }

    public func pause() {
        session.pause()
        isRunning = false
        trackingDescription = "AR session paused."
    }

    public func setBrushSamplePoint(_ point: CGPoint, in previewSize: CGSize) {
        guard previewSize.width > 0, previewSize.height > 0 else {
            normalizedBrushSamplePoint = CGPoint(x: 0.5, y: 0.5)
            brushPreviewSize = nil
            return
        }

        normalizedBrushSamplePoint = CGPoint(
            x: point.x / previewSize.width,
            y: point.y / previewSize.height
        )
        brushPreviewSize = previewSize
    }

    public func captureStrokeSourceImage() {
        guard
            let pixelBuffer = session.currentFrame?.capturedImage,
            let sourceImage = frameCapture.makeSourceImage(from: pixelBuffer)
        else {
            strokeSourceImage = nil
            hasStrokeSourceImage = false
            return
        }

        strokeSourceImage = sourceImage
        hasStrokeSourceImage = true
    }

    public func clearStrokeSourceImage() {
        strokeSourceImage = nil
        hasStrokeSourceImage = false
    }

    public func makeBrushSection(angleRadians: CGFloat) -> CGImage? {
        guard let strokeSourceImage else {
            return nil
        }

        return frameCapture.makeBrushSection(
            from: strokeSourceImage,
            angleRadians: angleRadians,
            normalizedPreviewPoint: normalizedBrushSamplePoint,
            previewSize: brushPreviewSize
        )
    }

    private func update(with pose: CameraPose, trackingDescription: String) {
        latestPose = pose
        self.trackingDescription = trackingDescription
    }

    private func updateFailure(_ message: String) {
        isRunning = false
        trackingDescription = message
    }
}

extension ARSessionManager: ARSessionDelegate {
    nonisolated public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let pose = CameraPose(transform: frame.camera.transform, timestamp: frame.timestamp)
        let trackingDescription = describeTrackingState(frame.camera.trackingState)

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.update(with: pose, trackingDescription: trackingDescription)
        }
    }

    nonisolated public func session(_ session: ARSession, didFailWithError error: any Error) {
        let message = "AR session failed: \(error.localizedDescription)"

        Task { @MainActor [weak self] in
            self?.updateFailure(message)
        }
    }

    nonisolated public func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor [weak self] in
            self?.trackingDescription = "AR session interrupted."
        }
    }

    nonisolated public func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor [weak self] in
            self?.trackingDescription = "AR interruption ended. Restarting tracking..."
            self?.start()
        }
    }
}

private func describeTrackingState(_ trackingState: ARCamera.TrackingState) -> String {
    switch trackingState {
    case .notAvailable:
        "Tracking unavailable"
    case .normal:
        "Tracking normal"
    case .limited(let reason):
        "Tracking limited: \(describeTrackingReason(reason))"
    }
}

private func describeTrackingReason(_ reason: ARCamera.TrackingState.Reason) -> String {
    switch reason {
    case .excessiveMotion:
        "excessive motion"
    case .initializing:
        "initializing"
    case .insufficientFeatures:
        "insufficient features"
    case .relocalizing:
        "relocalizing"
    @unknown default:
        "unknown reason"
    }
}
