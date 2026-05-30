import SwiftUI
import UIKit

public struct StrokeTouchSurface: UIViewRepresentable {
    private let onDragChanged: (BrushDragConfiguration, CGSize) -> Void
    private let onDragEnded: (BrushDragConfiguration, CGSize) -> Void
    private let onDragCancelled: () -> Void

    public init(
        onDragChanged: @escaping (BrushDragConfiguration, CGSize) -> Void,
        onDragEnded: @escaping (BrushDragConfiguration, CGSize) -> Void,
        onDragCancelled: @escaping () -> Void = {}
    ) {
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        self.onDragCancelled = onDragCancelled
    }

    public func makeUIView(context: Context) -> StrokeTouchUIView {
        let view = StrokeTouchUIView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isMultipleTouchEnabled = false
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        view.onDragCancelled = onDragCancelled
        return view
    }

    public func updateUIView(_ uiView: StrokeTouchUIView, context: Context) {
        uiView.onDragChanged = onDragChanged
        uiView.onDragEnded = onDragEnded
        uiView.onDragCancelled = onDragCancelled
    }
}

public final class StrokeTouchUIView: UIView {
    public var onDragChanged: ((BrushDragConfiguration, CGSize) -> Void)?
    public var onDragEnded: ((BrushDragConfiguration, CGSize) -> Void)?
    public var onDragCancelled: (() -> Void)?
    private var touchStart: CGPoint?

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else {
            return
        }

        let location = touch.location(in: self)
        touchStart = location
        onDragChanged?(
            BrushDragConfiguration(startPoint: location, endPoint: location),
            bounds.size
        )
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let touchStart else {
            return
        }

        onDragChanged?(
            BrushDragConfiguration(startPoint: touchStart, endPoint: touch.location(in: self)),
            bounds.size
        )
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let touchStart else {
            return
        }

        onDragEnded?(
            BrushDragConfiguration(startPoint: touchStart, endPoint: touch.location(in: self)),
            bounds.size
        )
        self.touchStart = nil
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchStart = nil
        onDragCancelled?()
    }
}
