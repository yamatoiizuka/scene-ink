import CoreGraphics

public struct BrushDragConfiguration: Equatable {
    public static let minimumDrawableWidth: CGFloat = 4

    public let startPoint: CGPoint
    public let endPoint: CGPoint
    public let width: CGFloat
    public let angleRadians: CGFloat

    public init(startPoint: CGPoint, endPoint: CGPoint) {
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y

        self.startPoint = startPoint
        self.endPoint = endPoint
        self.width = sqrt((dx * dx) + (dy * dy))
        self.angleRadians = Self.normalizedAngleFromLeft(dx: dx, dy: dy)
    }

    public var isDrawable: Bool {
        width >= Self.minimumDrawableWidth
    }

    nonisolated public static func normalizedAngleFromLeft(dx: CGFloat, dy: CGFloat) -> CGFloat {
        guard dx != 0 || dy != 0 else {
            return 0
        }

        let angle = atan2(dy, -dx)
        if angle >= 0 {
            return angle
        }

        return angle + (.pi * 2)
    }

    nonisolated public static func degrees(from angleRadians: CGFloat) -> CGFloat {
        angleRadians * 180 / .pi
    }
}
