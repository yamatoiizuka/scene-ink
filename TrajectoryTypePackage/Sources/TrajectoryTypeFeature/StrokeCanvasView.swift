import SwiftUI
import UIKit

public struct StrokeCanvasView: UIViewRepresentable {
    private let samples: [ScreenStrokeSample]

    public init(samples: [ScreenStrokeSample]) {
        self.samples = samples
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
        uiView.samples = samples
    }
}

public final class StrokeCompositorUIView: UIView {
    public var samples: [ScreenStrokeSample] = [] {
        didSet {
            setNeedsDisplay()
        }
    }

    public override func draw(_ rect: CGRect) {
        guard samples.count > 1, let context = UIGraphicsGetCurrentContext() else {
            return
        }

        for index in samples.indices.dropFirst() {
            drawSegment(from: samples[index - 1], to: samples[index], in: context)
        }

        strokeRibbonOutline(makeRibbonPath(in: bounds.size), in: context)
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
        let cross = averageCrossVector(from: previous, to: current)
        let width = (previous.width + current.width) / 2
        let center = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let segmentPath = makeSegmentPath(from: previous, to: current)

        context.saveGState()
        context.addPath(segmentPath.cgPath)
        context.clip()
        context.concatenate(
            CGAffineTransform(
                a: tangent.dx * length,
                b: tangent.dy * length,
                c: cross.dx * width,
                d: cross.dy * width,
                tx: center.x,
                ty: center.y
            )
        )

        let destination = CGRect(x: -0.5, y: -0.5, width: 1, height: 1)

        guard let brushSectionImage = current.brushSectionImage ?? previous.brushSectionImage else {
            context.restoreGState()
            return
        }

        UIImage(cgImage: brushSectionImage).draw(in: destination, blendMode: .normal, alpha: 0.98)
        context.restoreGState()
    }

    private func strokeRibbonOutline(_ ribbonPath: UIBezierPath, in context: CGContext) {
        context.saveGState()
        context.addPath(ribbonPath.cgPath)
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.45).cgColor)
        context.setLineWidth(1.5)
        context.strokePath()
        context.restoreGState()
    }

    private func averageCrossVector(from previous: ScreenStrokeSample, to current: ScreenStrokeSample) -> CGVector {
        let previousVector = FrameCapture.crossVector(forBrushAngle: previous.brushAngleRadians)
        let currentVector = FrameCapture.crossVector(forBrushAngle: current.brushAngleRadians)
        let dx = previousVector.dx + currentVector.dx
        let dy = previousVector.dy + currentVector.dy
        let length = sqrt((dx * dx) + (dy * dy))

        guard length > 0.001 else {
            return currentVector
        }

        return CGVector(dx: dx / length, dy: dy / length)
    }

    private func makeRibbonPath(in size: CGSize) -> UIBezierPath {
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

    private func makeSegmentPath(
        from previous: ScreenStrokeSample,
        to current: ScreenStrokeSample
    ) -> UIBezierPath {
        let previousEdges = edgePoints(for: previous)
        let currentEdges = edgePoints(for: current)
        let path = UIBezierPath()

        path.move(to: previousEdges.left)
        path.addLine(to: currentEdges.left)
        path.addLine(to: currentEdges.right)
        path.addLine(to: previousEdges.right)
        path.close()

        return path
    }

    private func edgePoints(for sample: ScreenStrokeSample) -> (left: CGPoint, right: CGPoint) {
        let point = sample.point(in: bounds.size)
        let direction = FrameCapture.crossVector(forBrushAngle: sample.brushAngleRadians)
        let halfWidth = sample.width / 2
        let offset = CGVector(dx: direction.dx * halfWidth, dy: direction.dy * halfWidth)

        return (
            left: CGPoint(x: point.x + offset.dx, y: point.y + offset.dy),
            right: CGPoint(x: point.x - offset.dx, y: point.y - offset.dy)
        )
    }
}
