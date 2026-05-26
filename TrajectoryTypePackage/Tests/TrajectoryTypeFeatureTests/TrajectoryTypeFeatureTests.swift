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

    recorder.begin()
    recorder.record(pose: CameraPose(transform: matrix_identity_float4x4, timestamp: 1), in: viewportSize)
    recorder.record(pose: CameraPose(transform: translated, timestamp: 2), in: viewportSize)

    #expect(recorder.samples.count == 2)
    #expect(abs(recorder.samples[0].normalizedPoint.x - 0.5) < 0.000_1)
    #expect(abs(recorder.samples[0].normalizedPoint.y - 0.5) < 0.000_1)
    #expect(recorder.samples[1].normalizedPoint.x > recorder.samples[0].normalizedPoint.x)
    #expect(recorder.samples[1].normalizedPoint.y < recorder.samples[0].normalizedPoint.y)
}
