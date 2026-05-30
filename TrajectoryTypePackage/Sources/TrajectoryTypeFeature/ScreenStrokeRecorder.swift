import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
public final class ScreenStrokeRecorder {
    public private(set) var strokes: [ScreenStroke] = []
    public private(set) var activeSamples: [ScreenStrokeSample] = []
    public private(set) var isRecording = false
    public private(set) var currentBrushAngleRadians: CGFloat = 0

    private var lastRenderedPoint: CGPoint?
    private var lastBrushAngleRadians: CGFloat = 0
    private var lastWidth: CGFloat = 0

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
        brushAngleRadians: CGFloat
    ) {
        activeSamples.removeAll(keepingCapacity: true)
        currentBrushAngleRadians = brushAngleRadians
        lastRenderedPoint = nil
        lastBrushAngleRadians = brushAngleRadians
        lastWidth = 0
        isRecording = true
    }

    public func end() {
        if !activeSamples.isEmpty {
            strokes.append(ScreenStroke(samples: activeSamples))
        }

        activeSamples.removeAll(keepingCapacity: true)
        lastRenderedPoint = nil
        isRecording = false
    }

    public func clear() {
        strokes.removeAll(keepingCapacity: true)
        activeSamples.removeAll(keepingCapacity: true)
        currentBrushAngleRadians = 0
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
        point: CGPoint,
        in viewportSize: CGSize,
        brushWidth: CGFloat,
        timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime,
        brushSectionProvider: (CGFloat, CGPoint) -> CGImage? = { _, _ in nil }
    ) {
        guard isRecording, viewportSize.width > 0, viewportSize.height > 0 else {
            return
        }

        let brushAngleRadians = lastRenderedPoint.map {
            Self.brushAngle(forDragFrom: $0, to: point, fallback: currentBrushAngleRadians)
        } ?? currentBrushAngleRadians
        currentBrushAngleRadians = brushAngleRadians

        if shouldAppend(point: point, brushWidth: brushWidth, brushAngleRadians: brushAngleRadians) {
            let normalizedSamplePoint = Self.normalizedPoint(for: point, in: viewportSize)
            append(
                point: point,
                brushWidth: brushWidth,
                brushAngleRadians: brushAngleRadians,
                timestamp: timestamp,
                viewportSize: viewportSize,
                brushSectionImage: brushSectionProvider(brushAngleRadians, normalizedSamplePoint)
            )
        }
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

    nonisolated public static func angularDistance(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat {
        let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: .pi * 2)
        return min(difference, (.pi * 2) - difference)
    }

    nonisolated public static func brushAngle(
        forDragFrom start: CGPoint,
        to end: CGPoint,
        fallback: CGFloat = 0
    ) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt((dx * dx) + (dy * dy))

        guard length > 0.001 else {
            return fallback
        }

        return normalizedAngle(atan2(dx / length, dy / length))
    }

    nonisolated public static func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        let fullTurn = CGFloat.pi * 2
        let normalized = angle.truncatingRemainder(dividingBy: fullTurn)

        if normalized >= 0 {
            return normalized
        }

        return normalized + fullTurn
    }
}
