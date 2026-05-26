import CoreGraphics
import Foundation

public struct ScreenStrokeSample: Identifiable {
    public let id: UUID
    public let normalizedPoint: CGPoint
    public let brushAngleRadians: CGFloat
    public let width: CGFloat
    public let timestamp: TimeInterval
    public let brushSectionImage: CGImage?

    public init(
        id: UUID = UUID(),
        normalizedPoint: CGPoint,
        brushAngleRadians: CGFloat,
        width: CGFloat,
        timestamp: TimeInterval,
        brushSectionImage: CGImage? = nil
    ) {
        self.id = id
        self.normalizedPoint = normalizedPoint
        self.brushAngleRadians = brushAngleRadians
        self.width = width
        self.timestamp = timestamp
        self.brushSectionImage = brushSectionImage
    }

    public func point(in size: CGSize) -> CGPoint {
        CGPoint(
            x: normalizedPoint.x * size.width,
            y: normalizedPoint.y * size.height
        )
    }
}
