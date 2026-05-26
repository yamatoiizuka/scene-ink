import SwiftUI

public struct StrokeCanvasView: View {
    private let samples: [ScreenStrokeSample]

    public init(samples: [ScreenStrokeSample]) {
        self.samples = samples
    }

    public var body: some View {
        Canvas { context, size in
            guard samples.count > 1 else {
                return
            }

            let ribbonPath = makeRibbonPath(in: size)
            context.fill(ribbonPath, with: .color(.white.opacity(0.88)))

            var centerline = Path()
            centerline.addLines(samples.map { $0.point(in: size) })
            context.stroke(centerline, with: .color(.black.opacity(0.2)), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func makeRibbonPath(in size: CGSize) -> Path {
        let edges = samples.map { sample in
            let point = sample.point(in: size)
            let direction = CGSize(
                width: cos(sample.rollRadians),
                height: sin(sample.rollRadians)
            )
            let halfWidth = sample.width / 2
            let offset = CGSize(
                width: direction.width * halfWidth,
                height: direction.height * halfWidth
            )

            return (
                left: CGPoint(x: point.x + offset.width, y: point.y + offset.height),
                right: CGPoint(x: point.x - offset.width, y: point.y - offset.height)
            )
        }

        var path = Path()
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

        path.closeSubpath()
        return path
    }
}
