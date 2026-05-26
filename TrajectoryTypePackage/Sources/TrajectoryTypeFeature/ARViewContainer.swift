import ARKit
import SceneKit
import SwiftUI

@MainActor
public struct ARViewContainer: UIViewRepresentable {
    private let sessionManager: ARSessionManager

    public init(sessionManager: ARSessionManager) {
        self.sessionManager = sessionManager
    }

    public func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = sessionManager.session
        view.scene = SCNScene()
        view.automaticallyUpdatesLighting = true
        view.backgroundColor = .black
        return view
    }

    public func updateUIView(_ uiView: ARSCNView, context: Context) {
        if uiView.session !== sessionManager.session {
            uiView.session = sessionManager.session
        }
    }
}
