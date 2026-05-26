import Foundation
import SwiftUI

@MainActor
public struct ContentView: View {
    @State private var sessionManager = ARSessionManager()

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            ARViewContainer(sessionManager: sessionManager)
                .ignoresSafeArea()

            debugOverlay
                .padding()
        }
        .onAppear {
            sessionManager.start()
        }
        .onDisappear {
            sessionManager.pause()
        }
    }

    public init() {}

    private var debugOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sessionManager.trackingDescription)
                .font(.system(.footnote, design: .rounded))

            if let pose = sessionManager.latestPose {
                Text("pos: \(pose.positionDescription)")
                Text("rot: \(pose.rotationDescription) deg")
                Text("time: \(String(format: "%.2f", pose.timestamp))")
            } else {
                Text("pos: waiting")
                Text("rot: waiting")
                Text("time: waiting")
            }
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AR tracking debug information")
    }
}
