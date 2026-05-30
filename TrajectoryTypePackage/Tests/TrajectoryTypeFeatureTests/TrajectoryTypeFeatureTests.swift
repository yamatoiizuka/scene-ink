import CoreGraphics
import Foundation
import simd
import Testing
@testable import TrajectoryTypeFeature

@Test func cameraPoseExtractsTranslation() async throws {
    var transform = matrix_identity_float4x4
    transform.columns.3 = SIMD4<Float>(1.25, -2.5, 3.75, 1)

    let pose = CameraPose(transform: transform, timestamp: 42)

    #expect(abs(pose.position.x - 1.25) < 0.000_1)
    #expect(abs(pose.position.y + 2.5) < 0.000_1)
    #expect(abs(pose.position.z - 3.75) < 0.000_1)
    #expect(pose.timestamp == 42)
}

@MainActor
@Test func screenStrokeRecorderMapsCameraTranslationToScreenSpace() async throws {
    let recorder = ScreenStrokeRecorder()
    let viewportSize = CGSize(width: 400, height: 800)
    var translated = matrix_identity_float4x4
    translated.columns.3 = SIMD4<Float>(0.05, 0.03, 0, 1)

    recorder.begin(
        at: CGPoint(x: 200, y: 400),
        in: viewportSize,
        pose: CameraPose(transform: matrix_identity_float4x4, timestamp: 0),
        brushAngleRadians: 0
    )
    recorder.record(
        pose: CameraPose(transform: matrix_identity_float4x4, timestamp: 1),
        in: viewportSize,
        brushWidth: 12
    )
    recorder.record(
        pose: CameraPose(transform: translated, timestamp: 2),
        in: viewportSize,
        brushWidth: 12
    )

    #expect(recorder.activeSamples.count == 2)
    #expect(abs(recorder.activeSamples[0].normalizedPoint.x - 0.5) < 0.000_1)
    #expect(abs(recorder.activeSamples[0].normalizedPoint.y - 0.5) < 0.000_1)
    #expect(recorder.activeSamples[1].normalizedPoint.x > recorder.activeSamples[0].normalizedPoint.x)
    #expect(recorder.activeSamples[1].normalizedPoint.y > recorder.activeSamples[0].normalizedPoint.y)
}

@Test func screenTranslationRotatesCameraAxesIntoPortraitScreenAxes() async throws {
    let cameraLocalX = ScreenStrokeRecorder.projectedScreenTranslation(from: SIMD3<Float>(1, 0, 0))
    let cameraLocalY = ScreenStrokeRecorder.projectedScreenTranslation(from: SIMD3<Float>(0, 1, 0))

    #expect(abs(cameraLocalX.x) < 0.000_1)
    #expect(cameraLocalX.y > 0)
    #expect(cameraLocalY.x > 0)
    #expect(abs(cameraLocalY.y) < 0.000_1)
}

@Test func projectedScreenTranslationDropsDepthAxis() async throws {
    let depthOnly = ScreenStrokeRecorder.projectedScreenTranslation(from: SIMD3<Float>(0, 0, 1))
    let mixed = ScreenStrokeRecorder.projectedScreenTranslation(from: SIMD3<Float>(0.03, 0.05, 4))
    let projected = ScreenStrokeRecorder.projectedScreenTranslation(from: SIMD3<Float>(0.03, 0.05, 0))

    #expect(abs(depthOnly.x) < 0.000_1)
    #expect(abs(depthOnly.y) < 0.000_1)
    #expect(abs(mixed.x - projected.x) < 0.000_1)
    #expect(abs(mixed.y - projected.y) < 0.000_1)
}

@MainActor
@Test func screenStrokeRecorderAddsDeviceAngleDeltaToInitialBrushAngle() async throws {
    let recorder = ScreenStrokeRecorder()
    let viewportSize = CGSize(width: 400, height: 800)
    var rotated = transform(rotatedAroundZ: .pi / 2)
    rotated.columns.3 = SIMD4<Float>(0.02, 0.02, 0, 1)

    recorder.begin(
        at: CGPoint(x: 120, y: 300),
        in: viewportSize,
        pose: CameraPose(transform: matrix_identity_float4x4, timestamp: 0),
        brushAngleRadians: .pi / 4
    )
    recorder.record(
        pose: CameraPose(transform: matrix_identity_float4x4, timestamp: 1),
        in: viewportSize,
        brushWidth: 12
    )
    recorder.record(
        pose: CameraPose(transform: rotated, timestamp: 2),
        in: viewportSize,
        brushWidth: 12
    )

    #expect(recorder.activeSamples.count == 2)
    #expect(abs(recorder.activeSamples[0].brushAngleRadians - (.pi / 4)) < 0.000_1)
    #expect(abs(recorder.activeSamples[1].brushAngleRadians - (3 * .pi / 4)) < 0.000_1)
}

@Test func deviceAngleDeltaIgnoresOutOfScreenPlaneTilt() async throws {
    let tiltedAroundY = transform(rotatedAroundY: .pi * 0.75)
    let tiltedAroundX = transform(rotatedAroundX: -.pi * 0.75)

    let yDelta = ScreenStrokeRecorder.deviceAngleDelta(
        from: matrix_identity_float4x4,
        to: tiltedAroundY
    )
    let xDelta = ScreenStrokeRecorder.deviceAngleDelta(
        from: matrix_identity_float4x4,
        to: tiltedAroundX
    )

    #expect(abs(yDelta) < 0.000_1)
    #expect(abs(xDelta) < 0.000_1)
}

@MainActor
@Test func screenStrokeRecorderRotatesActiveStrokeAroundStartPointForDisplay() async throws {
    let recorder = ScreenStrokeRecorder()
    let viewportSize = CGSize(width: 400, height: 800)
    let startPoint = CGPoint(x: 200, y: 400)
    var rotatedAndTranslated = transform(rotatedAroundZ: .pi / 2)
    rotatedAndTranslated.columns.3 = SIMD4<Float>(0.05, 0, 0, 1)

    recorder.begin(
        at: startPoint,
        in: viewportSize,
        pose: CameraPose(transform: matrix_identity_float4x4, timestamp: 0),
        brushAngleRadians: 0
    )
    recorder.record(
        pose: CameraPose(transform: matrix_identity_float4x4, timestamp: 1),
        in: viewportSize,
        brushWidth: 12
    )
    recorder.record(
        pose: CameraPose(transform: rotatedAndTranslated, timestamp: 2),
        in: viewportSize,
        brushWidth: 12
    )

    let rawPoint = recorder.activeSamples[1].point(in: viewportSize)
    let displayPoint = try #require(recorder.displayStrokes.last?.samples[1].point(in: viewportSize))

    #expect(abs(rawPoint.x - 200) < 0.000_1)
    #expect(abs(rawPoint.y - 460) < 0.000_1)
    #expect(abs(displayPoint.x - 140) < 0.000_1)
    #expect(abs(displayPoint.y - 400) < 0.000_1)
}

@Test func brushDragConfigurationUsesDragVectorForWidthAndAngle() async throws {
    let left = BrushDragConfiguration(
        startPoint: CGPoint(x: 40, y: 50),
        endPoint: CGPoint(x: 8, y: 50)
    )
    let down = BrushDragConfiguration(
        startPoint: CGPoint(x: 40, y: 50),
        endPoint: CGPoint(x: 40, y: 82)
    )

    #expect(abs(left.width - 32) < 0.000_1)
    #expect(abs(left.angleRadians) < 0.000_1)
    #expect(abs(down.width - 32) < 0.000_1)
    #expect(abs(down.angleRadians - (.pi / 2)) < 0.000_1)
}

@Test func frameCaptureMapsTapPointIntoCameraImageCoordinates() async throws {
    let sourceExtent = CGRect(x: 0, y: 0, width: 100, height: 200)

    let topLeft = FrameCapture.sourcePoint(
        in: sourceExtent,
        normalizedPreviewPoint: CGPoint(x: 0, y: 0)
    )
    let center = FrameCapture.sourcePoint(
        in: sourceExtent,
        normalizedPreviewPoint: CGPoint(x: 0.5, y: 0.5)
    )

    #expect(abs(topLeft.x) < 0.000_1)
    #expect(abs(topLeft.y - 200) < 0.000_1)
    #expect(abs(center.x - 50) < 0.000_1)
    #expect(abs(center.y - 100) < 0.000_1)
}

@Test func frameCaptureAccountsForAspectFillPreviewCropping() async throws {
    let sourceExtent = CGRect(x: 0, y: 0, width: 200, height: 100)

    let leftCenter = FrameCapture.sourcePoint(
        in: sourceExtent,
        normalizedPreviewPoint: CGPoint(x: 0, y: 0.5),
        previewSize: CGSize(width: 100, height: 100)
    )
    let rightCenter = FrameCapture.sourcePoint(
        in: sourceExtent,
        normalizedPreviewPoint: CGPoint(x: 1, y: 0.5),
        previewSize: CGSize(width: 100, height: 100)
    )

    #expect(abs(leftCenter.x - 50) < 0.000_1)
    #expect(abs(leftCenter.y - 50) < 0.000_1)
    #expect(abs(rightCenter.x - 150) < 0.000_1)
    #expect(abs(rightCenter.y - 50) < 0.000_1)
}

@MainActor
@Test func endingRecorderCommitsActiveStrokeInDrawOrder() async throws {
    let recorder = ScreenStrokeRecorder()
    let viewportSize = CGSize(width: 400, height: 800)
    var translated = matrix_identity_float4x4
    translated.columns.3 = SIMD4<Float>(0.02, 0.02, 0, 1)

    recorder.begin(
        at: CGPoint(x: 120, y: 300),
        in: viewportSize,
        pose: CameraPose(transform: matrix_identity_float4x4, timestamp: 0),
        brushAngleRadians: 0
    )
    recorder.record(
        pose: CameraPose(transform: matrix_identity_float4x4, timestamp: 1),
        in: viewportSize,
        brushWidth: 12
    )
    recorder.record(
        pose: CameraPose(transform: translated, timestamp: 2),
        in: viewportSize,
        brushWidth: 12
    )
    recorder.end()

    #expect(recorder.strokes.count == 1)
    #expect(recorder.activeSamples.isEmpty)
    #expect(recorder.displayStrokes.map(\.id) == recorder.strokes.map(\.id))
}

@MainActor
@Test func undoLastStrokeRemovesMostRecentCommittedStroke() async throws {
    let recorder = ScreenStrokeRecorder()
    let viewportSize = CGSize(width: 400, height: 800)
    var translated = matrix_identity_float4x4
    translated.columns.3 = SIMD4<Float>(0.02, 0.02, 0, 1)

    for index in 0..<2 {
        recorder.begin(
            at: CGPoint(x: 120, y: 300),
            in: viewportSize,
            pose: CameraPose(transform: matrix_identity_float4x4, timestamp: TimeInterval(index * 10)),
            brushAngleRadians: 0
        )
        recorder.record(
            pose: CameraPose(transform: matrix_identity_float4x4, timestamp: TimeInterval(index * 10 + 1)),
            in: viewportSize,
            brushWidth: 12
        )
        recorder.record(
            pose: CameraPose(transform: translated, timestamp: TimeInterval(index * 10 + 2)),
            in: viewportSize,
            brushWidth: 12
        )
        recorder.end()
    }

    let firstStrokeID = recorder.strokes[0].id
    let secondStrokeID = recorder.strokes[1].id

    recorder.undoLastStroke()

    #expect(recorder.strokes.count == 1)
    #expect(recorder.strokes[0].id == firstStrokeID)
    #expect(recorder.strokes.contains { $0.id == secondStrokeID } == false)
}

private func transform(rotatedAroundZ radians: Float) -> simd_float4x4 {
    var transform = matrix_identity_float4x4
    let c = Float(cos(Double(radians)))
    let s = Float(sin(Double(radians)))

    transform.columns.0 = SIMD4<Float>(c, s, 0, 0)
    transform.columns.1 = SIMD4<Float>(-s, c, 0, 0)

    return transform
}

private func transform(rotatedAroundY radians: Float) -> simd_float4x4 {
    var transform = matrix_identity_float4x4
    let c = Float(cos(Double(radians)))
    let s = Float(sin(Double(radians)))

    transform.columns.0 = SIMD4<Float>(c, 0, -s, 0)
    transform.columns.2 = SIMD4<Float>(s, 0, c, 0)

    return transform
}

private func transform(rotatedAroundX radians: Float) -> simd_float4x4 {
    var transform = matrix_identity_float4x4
    let c = Float(cos(Double(radians)))
    let s = Float(sin(Double(radians)))

    transform.columns.1 = SIMD4<Float>(0, c, s, 0)
    transform.columns.2 = SIMD4<Float>(0, -s, c, 0)

    return transform
}
