import Foundation
import simd

public struct CameraPose: Sendable {
    public let position: SIMD3<Float>
    public let rotationRadians: SIMD3<Float>
    public let timestamp: TimeInterval

    public init(transform: simd_float4x4, timestamp: TimeInterval) {
        self.position = Self.position(from: transform)
        self.rotationRadians = Self.eulerAngles(from: transform)
        self.timestamp = timestamp
    }

    public var positionDescription: String {
        "(\(Self.format(position.x)), \(Self.format(position.y)), \(Self.format(position.z)))"
    }

    public var rotationDescription: String {
        let degrees = rotationRadians * (180 / Float.pi)
        return "(\(Self.format(degrees.x)), \(Self.format(degrees.y)), \(Self.format(degrees.z)))"
    }

    public static func position(from transform: simd_float4x4) -> SIMD3<Float> {
        let translation = transform.columns.3
        return SIMD3(translation.x, translation.y, translation.z)
    }

    public static func eulerAngles(from transform: simd_float4x4) -> SIMD3<Float> {
        let m00 = transform.columns.0.x
        let m10 = transform.columns.0.y
        let m20 = transform.columns.0.z
        let m21 = transform.columns.1.z
        let m22 = transform.columns.2.z
        let m11 = transform.columns.1.y
        let m12 = transform.columns.2.y

        let horizontalMagnitude = sqrt((m00 * m00) + (m10 * m10))

        if horizontalMagnitude < 0.000_001 {
            return SIMD3(
                atan2(-m12, m11),
                atan2(-m20, horizontalMagnitude),
                0
            )
        }

        return SIMD3(
            atan2(m21, m22),
            atan2(-m20, horizontalMagnitude),
            atan2(m10, m00)
        )
    }

    private static func format(_ value: Float) -> String {
        String(format: "%.3f", value)
    }
}
