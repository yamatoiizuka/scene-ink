import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

public final class FrameCapture {
    private let context = CIContext(options: [.cacheIntermediates: false])

    public init() {}

    public func makeBrushSection(
        from pixelBuffer: CVPixelBuffer,
        angleRadians: CGFloat,
        outputSize: CGSize = CGSize(width: 1, height: 320),
        sourceWidthPixels: CGFloat = 1
    ) -> CGImage? {
        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        let sourceExtent = sourceImage.extent
        let center = CGPoint(x: sourceExtent.midX, y: sourceExtent.midY)
        let crossVector = Self.crossVector(forBrushAngle: angleRadians)
        let crossAngle = atan2(crossVector.dy, crossVector.dx)
        let rotationToVertical = (CGFloat.pi / 2) - crossAngle

        let rotated = sourceImage.transformed(
            by: CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: rotationToVertical)
                .translatedBy(x: -center.x, y: -center.y)
        )
        let rotatedExtent = rotated.extent
        let sectionHeight = min(rotatedExtent.width, rotatedExtent.height)
        let cropRect = CGRect(
            x: rotatedExtent.midX - (sourceWidthPixels / 2),
            y: rotatedExtent.midY - (sectionHeight / 2),
            width: sourceWidthPixels,
            height: sectionHeight
        )

        let scaleX = outputSize.width / cropRect.width
        let scaleY = outputSize.height / cropRect.height
        let cropped = rotated
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        return context.createCGImage(cropped, from: CGRect(origin: .zero, size: outputSize))
    }

    nonisolated public static func crossVector(forBrushAngle angleRadians: CGFloat) -> CGVector {
        CGVector(dx: -cos(angleRadians), dy: sin(angleRadians))
    }
}
