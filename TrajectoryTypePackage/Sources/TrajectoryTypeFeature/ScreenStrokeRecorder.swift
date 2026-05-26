import CoreGraphics
import Foundation
import Observation
import simd

@MainActor
@Observable
public final class ScreenStrokeRecorder {
    public private(set) var samples: [ScreenStrokeSample] = []
    public private(set) var isRecording = false

    private var anchorTransform: simd_float4x4?
    private var lastRenderedPoint: CGPoint?
    private var lastRollRadians: CGFloat = 0

    private let pointsPerScreen: CGFloat = 3
    private let sampleWidth: CGFloat = 34
    private let minimumPointDistance: CGFloat = 3
    private let minimumRollDelta: CGFloat = .pi / 90

    public init() {}

    public func begin() {
        samples.removeAll(keepingCapacity: true)
        anchorTransform = nil
        lastRenderedPoint = nil
        lastRollRadians = 0
        isRecording = true
    }

    public func end() {
        isRecording = false
    }

    public func clear() {
        samples.removeAll(keepingCapacity: true)
        anchorTransform = nil
        lastRenderedPoint = nil
        lastRollRadians = 0
        isRecording = false
    }

    public func record(pose: CameraPose, in viewportSize: CGSize) {
        guard isRecording, viewportSize.width > 0, viewportSize.height > 0 else {
            return
        }

        if anchorTransform == nil {
            anchorTransform = pose.transform
        }

        guard let anchorTransform else {
            return
        }

        let point = screenPoint(for: pose.transform, anchorTransform: anchorTransform, viewportSize: viewportSize)
        let rollRadians = CGFloat(Self.relativeRoll(from: anchorTransform, to: pose.transform))

        if shouldAppend(point: point, rollRadians: rollRadians) {
            append(point: point, rollRadians: rollRadians, timestamp: pose.timestamp, viewportSize: viewportSize)
        }
    }

    private func screenPoint(
        for transform: simd_float4x4,
        anchorTransform: simd_float4x4,
        viewportSize: CGSize
    ) -> CGPoint {
        let relative = Self.relativeTranslation(from: anchorTransform, to: transform)
        let pointsPerMeter = min(viewportSize.width, viewportSize.height) * pointsPerScreen

        return CGPoint(
            x: (viewportSize.width / 2) + (CGFloat(relative.x) * pointsPerMeter),
            y: (viewportSize.height / 2) - (CGFloat(relative.y) * pointsPerMeter)
        )
    }

    private func shouldAppend(point: CGPoint, rollRadians: CGFloat) -> Bool {
        guard let lastRenderedPoint else {
            return true
        }

        let dx = point.x - lastRenderedPoint.x
        let dy = point.y - lastRenderedPoint.y
        let distance = sqrt((dx * dx) + (dy * dy))
        let rollDelta = abs(rollRadians - lastRollRadians)

        return distance >= minimumPointDistance || rollDelta >= minimumRollDelta
    }

    private func append(
        point: CGPoint,
        rollRadians: CGFloat,
        timestamp: TimeInterval,
        viewportSize: CGSize
    ) {
        let normalizedPoint = CGPoint(
            x: point.x / viewportSize.width,
            y: point.y / viewportSize.height
        )

        samples.append(
            ScreenStrokeSample(
                normalizedPoint: normalizedPoint,
                rollRadians: rollRadians,
                width: sampleWidth,
                timestamp: timestamp
            )
        )

        lastRenderedPoint = point
        lastRollRadians = rollRadians
    }

    public static func relativeTranslation(
        from anchorTransform: simd_float4x4,
        to transform: simd_float4x4
    ) -> SIMD3<Float> {
        let position = transform.columns.3
        let relative = simd_inverse(anchorTransform) * SIMD4<Float>(position.x, position.y, position.z, 1)
        return SIMD3(relative.x, relative.y, relative.z)
    }

    public static func relativeRoll(
        from anchorTransform: simd_float4x4,
        to transform: simd_float4x4
    ) -> Float {
        let relativeTransform = simd_inverse(anchorTransform) * transform
        return CameraPose.eulerAngles(from: relativeTransform).z
    }
}
