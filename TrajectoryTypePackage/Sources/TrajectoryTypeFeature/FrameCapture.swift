import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

public final class FrameCapture {
    private let context = CIContext(options: [.cacheIntermediates: false])

    public init() {}

    public func makeBrushSection(
        from pixelBuffer: CVPixelBuffer,
        outputSize: CGSize = CGSize(width: 10, height: 220),
        sourceWidthRatio: CGFloat = 0.035
    ) -> CGImage? {
        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        let sourceExtent = sourceImage.extent
        let sectionWidth = max(8, sourceExtent.width * sourceWidthRatio)
        let cropRect = CGRect(
            x: sourceExtent.midX - (sectionWidth / 2),
            y: sourceExtent.minY,
            width: sectionWidth,
            height: sourceExtent.height
        )

        let scaleX = outputSize.width / cropRect.width
        let scaleY = outputSize.height / cropRect.height
        let cropped = sourceImage
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        return context.createCGImage(cropped, from: CGRect(origin: .zero, size: outputSize))
    }
}
