import SwiftUI
import UIKit

public struct StrokeCanvasView: UIViewRepresentable {
    private let strokes: [ScreenStroke]

    public init(strokes: [ScreenStroke]) {
        self.strokes = strokes
    }

    public func makeUIView(context: Context) -> StrokeCompositorUIView {
        let view = StrokeCompositorUIView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.contentMode = .redraw
        return view
    }

    public func updateUIView(_ uiView: StrokeCompositorUIView, context: Context) {
        uiView.strokes = strokes
    }
}

public final class StrokeCompositorUIView: UIView {
    private let sliceSpacing: CGFloat = 0.75
    private let sliceOverlap: CGFloat = 0.35
    private let maximumSlicesPerSegment = 160

    public var strokes: [ScreenStroke] = [] {
        didSet {
            setNeedsDisplay()
        }
    }

    public override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        for stroke in strokes where stroke.samples.count > 1 {
            drawStroke(stroke, in: context)
        }
    }

    private func drawStroke(_ stroke: ScreenStroke, in context: CGContext) {
        context.saveGState()
        context.addPath(makeRibbonPath(for: stroke.samples, in: bounds.size).cgPath)
        context.clip()
        context.interpolationQuality = .high

        for index in stroke.samples.indices.dropFirst() {
            drawSegment(from: stroke.samples[index - 1], to: stroke.samples[index], in: context)
        }

        context.restoreGState()
    }

    private func drawSegment(
        from previous: ScreenStrokeSample,
        to current: ScreenStrokeSample,
        in context: CGContext
    ) {
        let start = previous.point(in: bounds.size)
        let end = current.point(in: bounds.size)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt((dx * dx) + (dy * dy))

        guard length > 0.001 else {
            return
        }

        let tangent = CGVector(dx: dx / length, dy: dy / length)
        let sliceCount = min(maximumSlicesPerSegment, max(1, Int(ceil(length / sliceSpacing))))
        let stepLength = length / CGFloat(sliceCount)
        let sliceThickness = stepLength + sliceOverlap
        let previousImage = previous.brushSectionImage.map(UIImage.init(cgImage:))
        let currentImage = current.brushSectionImage.map(UIImage.init(cgImage:))

        guard previousImage != nil || currentImage != nil else {
            return
        }

        for index in 0...sliceCount {
            let t = CGFloat(index) / CGFloat(sliceCount)
            let center = CGPoint(
                x: start.x + (dx * t),
                y: start.y + (dy * t)
            )
            let width = interpolate(previous.width, current.width, t: t)
            let brushAngle = interpolateAngle(previous.brushAngleRadians, current.brushAngleRadians, t: t)
            let cross = FrameCapture.crossVector(forBrushAngle: brushAngle)

            drawSlice(
                center: center,
                tangent: tangent,
                cross: cross,
                thickness: sliceThickness,
                width: width,
                t: t,
                previousImage: previousImage,
                currentImage: currentImage,
                in: context
            )
        }
    }

    private func drawSlice(
        center: CGPoint,
        tangent: CGVector,
        cross: CGVector,
        thickness: CGFloat,
        width: CGFloat,
        t: CGFloat,
        previousImage: UIImage?,
        currentImage: UIImage?,
        in context: CGContext
    ) {
        let destination = CGRect(x: -0.5, y: -0.5, width: 1, height: 1)

        context.saveGState()
        context.concatenate(
            CGAffineTransform(
                a: tangent.dx * thickness,
                b: tangent.dy * thickness,
                c: cross.dx * width,
                d: cross.dy * width,
                tx: center.x,
                ty: center.y
            )
        )

        switch (previousImage, currentImage) {
        case let (previousImage?, currentImage?):
            previousImage.draw(in: destination, blendMode: .normal, alpha: 1)
            currentImage.draw(in: destination, blendMode: .normal, alpha: min(1, t))
        case let (previousImage?, nil):
            previousImage.draw(in: destination, blendMode: .normal, alpha: 1)
        case let (nil, currentImage?):
            currentImage.draw(in: destination, blendMode: .normal, alpha: 1)
        case (nil, nil):
            break
        }

        context.restoreGState()
    }

    private func makeRibbonPath(for samples: [ScreenStrokeSample], in size: CGSize) -> UIBezierPath {
        let edges = samples.map { sample in
            let point = sample.point(in: size)
            let direction = FrameCapture.crossVector(forBrushAngle: sample.brushAngleRadians)
            let halfWidth = sample.width / 2
            let offset = CGVector(dx: direction.dx * halfWidth, dy: direction.dy * halfWidth)

            return (
                left: CGPoint(x: point.x + offset.dx, y: point.y + offset.dy),
                right: CGPoint(x: point.x - offset.dx, y: point.y - offset.dy)
            )
        }

        let path = UIBezierPath()
        guard let first = edges.first else {
            return path
        }

        path.move(to: first.left)

        for edge in edges.dropFirst() {
            path.addLine(to: edge.left)
        }

        for edge in edges.reversed() {
            path.addLine(to: edge.right)
        }

        path.close()
        return path
    }

    private func interpolate(_ start: CGFloat, _ end: CGFloat, t: CGFloat) -> CGFloat {
        start + ((end - start) * t)
    }

    private func interpolateAngle(_ start: CGFloat, _ end: CGFloat, t: CGFloat) -> CGFloat {
        let delta = atan2(sin(end - start), cos(end - start))
        return start + (delta * t)
    }
}
