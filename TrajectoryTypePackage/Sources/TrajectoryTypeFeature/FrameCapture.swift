import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

public final class FrameCapture {
    private let context = CIContext(options: [.cacheIntermediates: false])

    public init() {}

    public func makeSourceImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        return context.createCGImage(sourceImage, from: sourceImage.extent)
    }

    public func makeBrushSection(
        from pixelBuffer: CVPixelBuffer,
        angleRadians: CGFloat,
        normalizedPreviewPoint: CGPoint = CGPoint(x: 0.5, y: 0.5),
        previewSize: CGSize? = nil,
        outputSize: CGSize = CGSize(width: 1, height: 320),
        sourceWidthPixels: CGFloat = 1
    ) -> CGImage? {
        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        return makeBrushSection(
            from: sourceImage,
            angleRadians: angleRadians,
            normalizedPreviewPoint: normalizedPreviewPoint,
            previewSize: previewSize,
            outputSize: outputSize,
            sourceWidthPixels: sourceWidthPixels
        )
    }

    public func makeBrushSection(
        from sourceCGImage: CGImage,
        angleRadians: CGFloat,
        normalizedPreviewPoint: CGPoint = CGPoint(x: 0.5, y: 0.5),
        previewSize: CGSize? = nil,
        outputSize: CGSize = CGSize(width: 1, height: 320),
        sourceWidthPixels: CGFloat = 1
    ) -> CGImage? {
        makeBrushSection(
            from: CIImage(cgImage: sourceCGImage),
            angleRadians: angleRadians,
            normalizedPreviewPoint: normalizedPreviewPoint,
            previewSize: previewSize,
            outputSize: outputSize,
            sourceWidthPixels: sourceWidthPixels
        )
    }

    private func makeBrushSection(
        from sourceImage: CIImage,
        angleRadians: CGFloat,
        normalizedPreviewPoint: CGPoint,
        previewSize: CGSize?,
        outputSize: CGSize,
        sourceWidthPixels: CGFloat
    ) -> CGImage? {
        let sourceExtent = sourceImage.extent
        let sampleCenter = Self.sourcePoint(
            in: sourceExtent,
            normalizedPreviewPoint: normalizedPreviewPoint,
            previewSize: previewSize
        )
        let crossVector = Self.crossVector(forBrushAngle: angleRadians)
        let crossAngle = atan2(crossVector.dy, crossVector.dx)
        let rotationToVertical = (CGFloat.pi / 2) - crossAngle

        let rotated = sourceImage.transformed(
            by: CGAffineTransform(translationX: sampleCenter.x, y: sampleCenter.y)
                .rotated(by: rotationToVertical)
                .translatedBy(x: -sampleCenter.x, y: -sampleCenter.y)
        )
        let rotatedExtent = rotated.extent
        let sectionHeight = min(rotatedExtent.width, rotatedExtent.height)
        let cropRect = CGRect(
            x: sampleCenter.x - (sourceWidthPixels / 2),
            y: sampleCenter.y - (sectionHeight / 2),
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

    nonisolated public static func sourcePoint(
        in sourceExtent: CGRect,
        normalizedPreviewPoint: CGPoint,
        previewSize: CGSize? = nil
    ) -> CGPoint {
        let normalized = CGPoint(
            x: clamp(normalizedPreviewPoint.x, in: 0...1),
            y: clamp(normalizedPreviewPoint.y, in: 0...1)
        )
        let visible = visibleSourceUnitRect(for: sourceExtent.size, previewSize: previewSize)
        let sourceX = visible.minX + (normalized.x * visible.width)
        let sourceYFromTop = visible.minY + (normalized.y * visible.height)

        return CGPoint(
            x: sourceExtent.minX + (sourceX * sourceExtent.width),
            y: sourceExtent.minY + ((1 - sourceYFromTop) * sourceExtent.height)
        )
    }

    nonisolated private static func visibleSourceUnitRect(
        for sourceSize: CGSize,
        previewSize: CGSize?
    ) -> CGRect {
        guard
            let previewSize,
            sourceSize.width > 0,
            sourceSize.height > 0,
            previewSize.width > 0,
            previewSize.height > 0
        else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        let sourceAspect = sourceSize.width / sourceSize.height
        let previewAspect = previewSize.width / previewSize.height

        if previewAspect < sourceAspect {
            let visibleWidth = previewAspect / sourceAspect
            return CGRect(x: (1 - visibleWidth) / 2, y: 0, width: visibleWidth, height: 1)
        }

        let visibleHeight = sourceAspect / previewAspect
        return CGRect(x: 0, y: (1 - visibleHeight) / 2, width: 1, height: visibleHeight)
    }

    nonisolated private static func clamp(_ value: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        min(range.upperBound, max(range.lowerBound, value))
    }
}
