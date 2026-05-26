import SwiftUI

public struct RotaryBrushControl: View {
    @Binding private var widthPixels: Int
    @Binding private var angleRadians: CGFloat

    private let widthRange: ClosedRange<Int>
    private let controlSize: CGFloat = 154
    private let thumbSize: CGFloat = 24

    public init(
        widthPixels: Binding<Int>,
        angleRadians: Binding<CGFloat>,
        widthRange: ClosedRange<Int> = 1...96
    ) {
        self._widthPixels = widthPixels
        self._angleRadians = angleRadians
        self.widthRange = widthRange
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = (size / 2) - (thumbSize / 2) - 8
            let thumbPoint = Self.point(
                center: center,
                radius: radius * normalizedWidth,
                angleRadians: angleRadians
            )

            ZStack {
                Circle()
                    .fill(.black.opacity(0.52))
                    .stroke(.white.opacity(0.18), lineWidth: 1)

                ForEach(0..<4) { index in
                    Capsule()
                        .fill(.white.opacity(index == 0 ? 0.42 : 0.18))
                        .frame(width: index == 0 ? 22 : 14, height: 2)
                        .offset(x: -radius)
                        .rotationEffect(.radians(Double(index) * .pi / 2))
                }

                Circle()
                    .fill(.white.opacity(0.2))
                    .frame(width: 10, height: 10)

                Path { path in
                    path.move(to: center)
                    path.addLine(to: thumbPoint)
                }
                .stroke(.white.opacity(0.42), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                Circle()
                    .fill(.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .position(thumbPoint)

                VStack(spacing: 2) {
                    Text("\(widthPixels)px")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                    Text("\(Int(Self.degrees(from: angleRadians).rounded()))°")
                        .font(.system(.caption2, design: .monospaced))
                }
                .foregroundStyle(.white)
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        update(location: value.location, center: center, radius: radius)
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Brush control")
            .accessibilityValue("\(widthPixels) pixels, \(Int(Self.degrees(from: angleRadians).rounded())) degrees")
        }
        .frame(width: controlSize, height: controlSize)
    }

    private var normalizedWidth: CGFloat {
        let span = CGFloat(widthRange.upperBound - widthRange.lowerBound)
        guard span > 0 else {
            return 0
        }

        return CGFloat(widthPixels - widthRange.lowerBound) / span
    }

    private func update(location: CGPoint, center: CGPoint, radius: CGFloat) {
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = min(sqrt((dx * dx) + (dy * dy)), radius)
        let normalizedDistance = radius > 0 ? distance / radius : 0
        let span = CGFloat(widthRange.upperBound - widthRange.lowerBound)
        let width = CGFloat(widthRange.lowerBound) + (normalizedDistance * span)

        widthPixels = min(widthRange.upperBound, max(widthRange.lowerBound, Int(width.rounded())))
        angleRadians = Self.normalizedAngleFromLeft(dx: dx, dy: dy)
    }

    nonisolated public static func normalizedAngleFromLeft(dx: CGFloat, dy: CGFloat) -> CGFloat {
        let angle = atan2(dy, -dx)
        if angle >= 0 {
            return angle
        }

        return angle + (.pi * 2)
    }

    nonisolated public static func point(center: CGPoint, radius: CGFloat, angleRadians: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x - (cos(angleRadians) * radius),
            y: center.y + (sin(angleRadians) * radius)
        )
    }

    nonisolated public static func degrees(from angleRadians: CGFloat) -> CGFloat {
        angleRadians * 180 / .pi
    }
}
