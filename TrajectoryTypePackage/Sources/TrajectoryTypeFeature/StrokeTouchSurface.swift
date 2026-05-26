import SwiftUI
import UIKit

public struct StrokeTouchSurface: UIViewRepresentable {
    private let onTap: (CGPoint, CGSize) -> Void

    public init(
        onTap: @escaping (CGPoint, CGSize) -> Void
    ) {
        self.onTap = onTap
    }

    public func makeUIView(context: Context) -> StrokeTouchUIView {
        let view = StrokeTouchUIView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isMultipleTouchEnabled = false
        view.onTap = onTap
        return view
    }

    public func updateUIView(_ uiView: StrokeTouchUIView, context: Context) {
        uiView.onTap = onTap
    }
}

public final class StrokeTouchUIView: UIView {
    public var onTap: ((CGPoint, CGSize) -> Void)?
    private var touchStart: CGPoint?

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else {
            return
        }

        touchStart = touch.location(in: self)
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let touchStart else {
            return
        }

        let location = touch.location(in: self)
        let dx = location.x - touchStart.x
        let dy = location.y - touchStart.y
        let distance = sqrt((dx * dx) + (dy * dy))

        if distance < 22 {
            onTap?(location, bounds.size)
        }

        self.touchStart = nil
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchStart = nil
    }
}
