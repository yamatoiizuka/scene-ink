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

        let ribbonPath = makeRibbonPath(in: bounds.size)
        context.saveGState()
        context.addPath(ribbonPath.cgPath)
        context.clip()

        for index in samples.indices {
            drawSample(samples[index], at: index, in: context)
        }

        context.restoreGState()
        strokeRibbonOutline(ribbonPath, in: context)
    }

    private func drawSample(_ sample: ScreenStrokeSample, at index: Int, in context: CGContext) {
        let point = sample.point(in: bounds.size)
        let tangent = tangentVector(at: index)
        let cross = CGVector(dx: cos(sample.rollRadians), dy: sin(sample.rollRadians))
        let patchLength = max(sample.width * 2.6, segmentLength(at: index) * 1.35)
        let patchWidth = sample.width * 1.55

        context.saveGState()
        context.concatenate(
            CGAffineTransform(
                a: tangent.dx * patchLength,
                b: tangent.dy * patchLength,
                c: cross.dx * patchWidth,
                d: cross.dy * patchWidth,
                tx: point.x,
                ty: point.y
            )
        )

        let destination = CGRect(x: -0.5, y: -0.5, width: 1, height: 1)

        if let capturedImage = sample.capturedImage {
            UIImage(cgImage: capturedImage).draw(in: destination, blendMode: .normal, alpha: 0.96)
        } else {
            UIColor.white.withAlphaComponent(0.88).setFill()
            UIRectFill(destination)
        }

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

    private func tangentVector(at index: Int) -> CGVector {
        let current = samples[index].point(in: bounds.size)
        let neighbor: CGPoint

        if index < samples.index(before: samples.endIndex) {
            neighbor = samples[index + 1].point(in: bounds.size)
        } else {
            neighbor = samples[index - 1].point(in: bounds.size)
        }

        let dx = neighbor.x - current.x
        let dy = neighbor.y - current.y
        let length = max(sqrt((dx * dx) + (dy * dy)), 0.001)
        return CGVector(dx: dx / length, dy: dy / length)
    }

    private func segmentLength(at index: Int) -> CGFloat {
        let current = samples[index].point(in: bounds.size)
        let neighbor: CGPoint

        if index < samples.index(before: samples.endIndex) {
            neighbor = samples[index + 1].point(in: bounds.size)
        } else {
            neighbor = samples[index - 1].point(in: bounds.size)
        }

        let dx = neighbor.x - current.x
        let dy = neighbor.y - current.y
        return sqrt((dx * dx) + (dy * dy))
    }

    private func makeRibbonPath(in size: CGSize) -> UIBezierPath {
        let edges = samples.map { sample in
            let point = sample.point(in: size)
            let direction = CGVector(dx: cos(sample.rollRadians), dy: sin(sample.rollRadians))
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
}
