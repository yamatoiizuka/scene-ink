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

    private var anchorTransform: simd_float4x4?
    private var startPoint: CGPoint?
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

    public func begin(at point: CGPoint, in viewportSize: CGSize, pose: CameraPose?) {
        activeSamples.removeAll(keepingCapacity: true)
        anchorTransform = pose?.transform
        startPoint = point
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
        lastRenderedPoint = nil
        isRecording = false
    }

    public func clear() {
        strokes.removeAll(keepingCapacity: true)
        activeSamples.removeAll(keepingCapacity: true)
        anchorTransform = nil
        startPoint = nil
        lastRenderedPoint = nil
        lastBrushAngleRadians = 0
        lastWidth = 0
        isRecording = false
    }

    public func record(
        pose: CameraPose,
        in viewportSize: CGSize,
        brushWidth: CGFloat,
        brushAngleRadians: CGFloat,
        brushSectionProvider: () -> CGImage? = { nil }
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

        let point = screenPoint(
            for: pose.transform,
            anchorTransform: anchorTransform,
            startPoint: startPoint,
            viewportSize: viewportSize
        )

        if shouldAppend(point: point, brushWidth: brushWidth, brushAngleRadians: brushAngleRadians) {
            append(
                point: point,
                brushWidth: brushWidth,
                brushAngleRadians: brushAngleRadians,
                timestamp: pose.timestamp,
                viewportSize: viewportSize,
                brushSectionImage: brushSectionProvider()
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
        let screenTranslation = Self.screenTranslation(from: relative) * Float(pointsPerMeter)

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
        let normalizedPoint = CGPoint(
            x: point.x / viewportSize.width,
            y: point.y / viewportSize.height
        )

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

    nonisolated public static func relativeTranslation(
        from anchorTransform: simd_float4x4,
        to transform: simd_float4x4
    ) -> SIMD3<Float> {
        let position = transform.columns.3
        let relative = simd_inverse(anchorTransform) * SIMD4<Float>(position.x, position.y, position.z, 1)
        return SIMD3(relative.x, relative.y, relative.z)
    }

    nonisolated public static func screenTranslation(from relativeTranslation: SIMD3<Float>) -> SIMD2<Float> {
        SIMD2(relativeTranslation.y, relativeTranslation.x)
    }

    nonisolated public static func angularDistance(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat {
        let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: .pi * 2)
        return min(difference, (.pi * 2) - difference)
    }
}
