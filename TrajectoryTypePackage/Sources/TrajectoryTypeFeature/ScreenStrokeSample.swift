import CoreGraphics
import Foundation

public struct ScreenStrokeSample: Identifiable {
    public let id: UUID
    public let normalizedPoint: CGPoint
    public let rollRadians: CGFloat
    public let width: CGFloat
    public let timestamp: TimeInterval

    public init(
        id: UUID = UUID(),
        normalizedPoint: CGPoint,
        rollRadians: CGFloat,
        width: CGFloat,
        timestamp: TimeInterval
    ) {
        self.id = id
        self.normalizedPoint = normalizedPoint
        self.rollRadians = rollRadians
        self.width = width
        self.timestamp = timestamp
    }

    public func point(in size: CGSize) -> CGPoint {
        CGPoint(
            x: normalizedPoint.x * size.width,
            y: normalizedPoint.y * size.height
        )
    }
}
