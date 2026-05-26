import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

public final class FrameCapture {
    private let context = CIContext(options: [.cacheIntermediates: false])

    public init() {}

    public func makeSnapshot(
        from pixelBuffer: CVPixelBuffer,
        maxPixelDimension: CGFloat = 480
    ) -> CGImage? {
        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        let scale = min(1, maxPixelDimension / max(sourceImage.extent.width, sourceImage.extent.height))
        let outputImage = sourceImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        return context.createCGImage(outputImage, from: outputImage.extent)
    }
}
