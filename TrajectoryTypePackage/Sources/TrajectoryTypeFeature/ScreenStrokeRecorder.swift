import CoreGraphics
import Foundation
import Observation
import simd

@MainActor
@Observable
public final class ScreenStrokeRecorder {
    public private(set) var strokes: [ScreenStroke] = []
    public private(set) var activeSamples: [ScreenStrokeSample] = []
    public private(set) var isRecording = false
    public private(set) var currentBrushAngleRadians: CGFloat = 0
    public private(set) var currentStrokeRotationRadians: CGFloat = 0

    private var anchorTransform: simd_float4x4?
    private var startPoint: CGPoint?
    private var initialBrushAngleRadians: CGFloat = 0
    private var lastRenderedPoint: CGPoint?
    private var lastBrushAngleRadians: CGFloat = 0
    private var lastWidth: CGFloat = 0

    private let pointsPerScreen: CGFloat = 3
    private let minimumPointDistance: CGFloat = 3
    private let minimumBrushAngleDelta: CGFloat = .pi / 90
    private let maxSamples = 260

    public init() {}

    public var displayStrokes: [ScreenStroke] {
        guard !activeSamples.isEmpty else {
            return strokes
        }

        return strokes + [ScreenStroke(samples: activeSamples)]
    }

    public var sampleCount: Int {
        strokes.reduce(activeSamples.count) { count, stroke in
            count + stroke.samples.count
        }
    }

    public var brushSectionSampleCount: Int {
        let committedCount = strokes.reduce(0) { count, stroke in
            count + stroke.samples.filter { $0.brushSectionImage != nil }.count
        }
        let activeCount = activeSamples.filter { $0.brushSectionImage != nil }.count

        return committedCount + activeCount
    }

    public func begin(
        at point: CGPoint,
        in viewportSize: CGSize,
        pose: CameraPose?,
        brushAngleRadians: CGFloat
    ) {
        activeSamples.removeAll(keepingCapacity: true)
        anchorTransform = pose?.transform
        startPoint = point
        initialBrushAngleRadians = brushAngleRadians
        currentBrushAngleRadians = brushAngleRadians
        currentStrokeRotationRadians = 0
        lastRenderedPoint = nil
        lastBrushAngleRadians = 0
        lastWidth = 0
        isRecording = true
    }

    public func end() {
        if !activeSamples.isEmpty {
            strokes.append(ScreenStroke(samples: activeSamples))
        }

        activeSamples.removeAll(keepingCapacity: true)
        anchorTransform = nil
        startPoint = nil
        currentStrokeRotationRadians = 0
        lastRenderedPoint = nil
        isRecording = false
    }

    public func clear() {
        strokes.removeAll(keepingCapacity: true)
        activeSamples.removeAll(keepingCapacity: true)
        anchorTransform = nil
        startPoint = nil
        initialBrushAngleRadians = 0
        currentBrushAngleRadians = 0
        currentStrokeRotationRadians = 0
        lastRenderedPoint = nil
        lastBrushAngleRadians = 0
        lastWidth = 0
        isRecording = false
    }

    public func undoLastStroke() {
        guard !strokes.isEmpty else {
            return
        }

        strokes.removeLast()
    }

    public func record(
        pose: CameraPose,
        in viewportSize: CGSize,
        brushWidth: CGFloat,
        brushSectionProvider: (CGFloat, CGPoint) -> CGImage? = { _, _ in nil }
    ) {
        guard isRecording, viewportSize.width > 0, viewportSize.height > 0 else {
            return
        }

        if anchorTransform == nil {
            anchorTransform = pose.transform
        }

        guard let anchorTransform, let startPoint else {
            return
        }

        let deviceAngleDelta = Self.deviceAngleDelta(from: anchorTransform, to: pose.transform)
        let brushAngleRadians = Self.brushAngle(
            initialBrushAngleRadians: initialBrushAngleRadians,
            deviceAngleDelta: deviceAngleDelta
        )
        currentBrushAngleRadians = brushAngleRadians
        currentStrokeRotationRadians = deviceAngleDelta

        let projectedPoint = screenPoint(
            for: pose.transform,
            anchorTransform: anchorTransform,
            startPoint: startPoint,
            viewportSize: viewportSize
        )
        let point = Self.rotate(
            point: projectedPoint,
            around: startPoint,
            angleRadians: deviceAngleDelta
        )
        let normalizedSamplePoint = Self.normalizedPoint(for: point, in: viewportSize)

        if shouldAppend(point: point, brushWidth: brushWidth, brushAngleRadians: brushAngleRadians) {
            append(
                point: point,
                brushWidth: brushWidth,
                brushAngleRadians: brushAngleRadians,
                timestamp: pose.timestamp,
                viewportSize: viewportSize,
                brushSectionImage: brushSectionProvider(brushAngleRadians, normalizedSamplePoint)
            )
        }
    }

    private func screenPoint(
        for transform: simd_float4x4,
        anchorTransform: simd_float4x4,
        startPoint: CGPoint,
        viewportSize: CGSize
    ) -> CGPoint {
        let relative = Self.relativeTranslation(from: anchorTransform, to: transform)
        let pointsPerMeter = min(viewportSize.width, viewportSize.height) * pointsPerScreen
        let screenTranslation = Self.projectedScreenTranslation(from: relative) * Float(pointsPerMeter)

        return CGPoint(
            x: startPoint.x + CGFloat(screenTranslation.x),
            y: startPoint.y + CGFloat(screenTranslation.y)
        )
    }

    private func shouldAppend(point: CGPoint, brushWidth: CGFloat, brushAngleRadians: CGFloat) -> Bool {
        guard let lastRenderedPoint else {
            return true
        }

        let dx = point.x - lastRenderedPoint.x
        let dy = point.y - lastRenderedPoint.y
        let distance = sqrt((dx * dx) + (dy * dy))
        let brushAngleDelta = Self.angularDistance(brushAngleRadians, lastBrushAngleRadians)
        let widthDelta = abs(brushWidth - lastWidth)

        return distance >= minimumPointDistance || brushAngleDelta >= minimumBrushAngleDelta || widthDelta >= 1
    }

    private func append(
        point: CGPoint,
        brushWidth: CGFloat,
        brushAngleRadians: CGFloat,
        timestamp: TimeInterval,
        viewportSize: CGSize,
        brushSectionImage: CGImage?
    ) {
        let normalizedPoint = Self.normalizedPoint(for: point, in: viewportSize)

        activeSamples.append(
            ScreenStrokeSample(
                normalizedPoint: normalizedPoint,
                brushAngleRadians: brushAngleRadians,
                width: brushWidth,
                timestamp: timestamp,
                brushSectionImage: brushSectionImage
            )
        )

        if activeSamples.count > maxSamples {
            activeSamples.removeFirst(activeSamples.count - maxSamples)
        }

        lastRenderedPoint = point
        lastBrushAngleRadians = brushAngleRadians
        lastWidth = brushWidth
    }

    nonisolated public static func normalizedPoint(for point: CGPoint, in viewportSize: CGSize) -> CGPoint {
        CGPoint(
            x: point.x / viewportSize.width,
            y: point.y / viewportSize.height
        )
    }

    nonisolated public static func relativeTranslation(
        from anchorTransform: simd_float4x4,
        to transform: simd_float4x4
    ) -> SIMD3<Float> {
        let position = transform.columns.3
        let relative = simd_inverse(anchorTransform) * SIMD4<Float>(position.x, position.y, position.z, 1)
        return SIMD3(relative.x, relative.y, relative.z)
    }

    nonisolated public static func screenTranslation(from relativeTranslation: SIMD3<Float>) -> SIMD2<Float> {
        projectedScreenTranslation(from: relativeTranslation)
    }

    nonisolated public static func projectedScreenTranslation(
        from relativeTranslation: SIMD3<Float>
    ) -> SIMD2<Float> {
        // Project onto the screen-parallel plane. Local z is camera depth and is intentionally discarded.
        SIMD2(relativeTranslation.y, relativeTranslation.x)
    }

    nonisolated public static func angularDistance(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat {
        let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: .pi * 2)
        return min(difference, (.pi * 2) - difference)
    }

    nonisolated public static func brushAngle(
        initialBrushAngleRadians: CGFloat,
        deviceAngleDelta: CGFloat
    ) -> CGFloat {
        normalizedAngle(initialBrushAngleRadians + deviceAngleDelta)
    }

    nonisolated public static func brushAngle(
        initialBrushAngleRadians: CGFloat,
        anchorTransform: simd_float4x4,
        currentTransform: simd_float4x4
    ) -> CGFloat {
        let delta = deviceAngleDelta(from: anchorTransform, to: currentTransform)
        return brushAngle(initialBrushAngleRadians: initialBrushAngleRadians, deviceAngleDelta: delta)
    }

    nonisolated public static func deviceAngleDelta(
        from anchorTransform: simd_float4x4,
        to transform: simd_float4x4
    ) -> CGFloat {
        let relative = simd_inverse(anchorTransform) * transform
        let rotationMatrix = simd_float3x3(
            SIMD3(relative.columns.0.x, relative.columns.0.y, relative.columns.0.z),
            SIMD3(relative.columns.1.x, relative.columns.1.y, relative.columns.1.z),
            SIMD3(relative.columns.2.x, relative.columns.2.y, relative.columns.2.z)
        )
        let rotation = simd_quatf(rotationMatrix)
        let scalar: Float
        let z: Float

        if rotation.real < 0 {
            scalar = -rotation.real
            z = -rotation.imag.z
        } else {
            scalar = rotation.real
            z = rotation.imag.z
        }

        guard abs(scalar) > 0.000_001 || abs(z) > 0.000_001 else {
            return 0
        }

        return CGFloat(2 * atan2(z, scalar))
    }

    nonisolated public static func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        let fullTurn = CGFloat.pi * 2
        let normalized = angle.truncatingRemainder(dividingBy: fullTurn)

        if normalized >= 0 {
            return normalized
        }

        return normalized + fullTurn
    }

    nonisolated public static func rotate(point: CGPoint, around anchor: CGPoint, angleRadians: CGFloat) -> CGPoint {
        let dx = point.x - anchor.x
        let dy = point.y - anchor.y
        let cosAngle = cos(angleRadians)
        let sinAngle = sin(angleRadians)

        return CGPoint(
            x: anchor.x + (dx * cosAngle) - (dy * sinAngle),
            y: anchor.y + (dx * sinAngle) + (dy * cosAngle)
        )
    }
}
