import CoreGraphics
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
        pose: CameraPose(transform: matrix_identity_float4x4, timestamp: 0)
    )
    recorder.record(
        pose: CameraPose(transform: matrix_identity_float4x4, timestamp: 1),
        in: viewportSize,
        brushWidth: 12,
        brushAngleRadians: 0
    )
    recorder.record(
        pose: CameraPose(transform: translated, timestamp: 2),
        in: viewportSize,
        brushWidth: 12,
        brushAngleRadians: 0
    )

    #expect(recorder.activeSamples.count == 2)
    #expect(abs(recorder.activeSamples[0].normalizedPoint.x - 0.5) < 0.000_1)
    #expect(abs(recorder.activeSamples[0].normalizedPoint.y - 0.5) < 0.000_1)
    #expect(recorder.activeSamples[1].normalizedPoint.x < recorder.activeSamples[0].normalizedPoint.x)
    #expect(recorder.activeSamples[1].normalizedPoint.y < recorder.activeSamples[0].normalizedPoint.y)
}

@Test func screenTranslationRotatesCameraAxesIntoPortraitScreenAxes() async throws {
    let cameraLocalX = ScreenStrokeRecorder.screenTranslation(from: SIMD3<Float>(1, 0, 0))
    let cameraLocalY = ScreenStrokeRecorder.screenTranslation(from: SIMD3<Float>(0, 1, 0))

    #expect(abs(cameraLocalX.x) < 0.000_1)
    #expect(cameraLocalX.y < 0)
    #expect(cameraLocalY.x < 0)
    #expect(abs(cameraLocalY.y) < 0.000_1)
}

@Test func rotaryBrushControlTreatsLeftAsZeroDegrees() async throws {
    let left = RotaryBrushControl.normalizedAngleFromLeft(dx: -1, dy: 0)
    let down = RotaryBrushControl.normalizedAngleFromLeft(dx: 0, dy: 1)

    #expect(abs(left) < 0.000_1)
    #expect(abs(down - (.pi / 2)) < 0.000_1)
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
        pose: CameraPose(transform: matrix_identity_float4x4, timestamp: 0)
    )
    recorder.record(
        pose: CameraPose(transform: matrix_identity_float4x4, timestamp: 1),
        in: viewportSize,
        brushWidth: 12,
        brushAngleRadians: 0
    )
    recorder.record(
        pose: CameraPose(transform: translated, timestamp: 2),
        in: viewportSize,
        brushWidth: 12,
        brushAngleRadians: 0
    )
    recorder.end()

    #expect(recorder.strokes.count == 1)
    #expect(recorder.activeSamples.isEmpty)
    #expect(recorder.displayStrokes.map(\.id) == recorder.strokes.map(\.id))
}
