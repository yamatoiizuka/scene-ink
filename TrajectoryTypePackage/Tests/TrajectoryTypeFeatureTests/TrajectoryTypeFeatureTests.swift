import simd
import Testing
@testable import TrajectoryTypeFeature

@Test func example() async throws {
    var transform = matrix_identity_float4x4
    transform.columns.3 = SIMD4<Float>(1.25, -2.5, 3.75, 1)

    let pose = CameraPose(transform: transform, timestamp: 42)

    #expect(abs(pose.position.x - 1.25) < 0.000_1)
    #expect(abs(pose.position.y + 2.5) < 0.000_1)
    #expect(abs(pose.position.z - 3.75) < 0.000_1)
    #expect(pose.timestamp == 42)
}
