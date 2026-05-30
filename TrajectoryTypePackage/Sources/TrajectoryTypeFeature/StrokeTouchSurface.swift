import SwiftUI
import UIKit

public struct StrokeTouchSurface: UIViewRepresentable {
    private let onDragBegan: (CGPoint, CGSize) -> Void
    private let onDragMoved: (CGPoint, CGSize) -> Void
    private let onDragEnded: (CGPoint, CGSize) -> Void
    private let onDragCancelled: () -> Void

    public init(
        onDragBegan: @escaping (CGPoint, CGSize) -> Void,
        onDragMoved: @escaping (CGPoint, CGSize) -> Void,
        onDragEnded: @escaping (CGPoint, CGSize) -> Void,
        onDragCancelled: @escaping () -> Void = {}
    ) {
        self.onDragBegan = onDragBegan
        self.onDragMoved = onDragMoved
        self.onDragEnded = onDragEnded
        self.onDragCancelled = onDragCancelled
    }

    public func makeUIView(context: Context) -> StrokeTouchUIView {
        let view = StrokeTouchUIView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isMultipleTouchEnabled = false
        view.onDragBegan = onDragBegan
        view.onDragMoved = onDragMoved
        view.onDragEnded = onDragEnded
        view.onDragCancelled = onDragCancelled
        return view
    }

    public func updateUIView(_ uiView: StrokeTouchUIView, context: Context) {
        uiView.onDragBegan = onDragBegan
        uiView.onDragMoved = onDragMoved
        uiView.onDragEnded = onDragEnded
        uiView.onDragCancelled = onDragCancelled
    }
}

public final class StrokeTouchUIView: UIView {
    public var onDragBegan: ((CGPoint, CGSize) -> Void)?
    public var onDragMoved: ((CGPoint, CGSize) -> Void)?
    public var onDragEnded: ((CGPoint, CGSize) -> Void)?
    public var onDragCancelled: (() -> Void)?

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else {
            return
        }

        let location = touch.location(in: self)
        onDragBegan?(location, bounds.size)
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else {
            return
        }

        onDragMoved?(touch.location(in: self), bounds.size)
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else {
            return
        }

        onDragEnded?(touch.location(in: self), bounds.size)
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        onDragCancelled?()
    }
}
