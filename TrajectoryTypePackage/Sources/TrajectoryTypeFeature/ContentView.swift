import Foundation
import SwiftUI

@MainActor
public struct ContentView: View {
    @State private var sessionManager = ARSessionManager()
    @State private var strokeRecorder = ScreenStrokeRecorder()

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                ARViewContainer(sessionManager: sessionManager)
                    .ignoresSafeArea()

                StrokeCanvasView(samples: strokeRecorder.samples)
                    .ignoresSafeArea()

                controls
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 28)

                debugOverlay
                    .padding(.leading)
                    .padding(.bottom, 104)
            }
            .onChange(of: sessionManager.latestPose?.timestamp) {
                guard let pose = sessionManager.latestPose else {
                    return
                }

                strokeRecorder.record(pose: pose, in: proxy.size) {
                    sessionManager.makeCurrentBrushSection()
                }
            }
        }
        .onAppear {
            sessionManager.start()
        }
        .onDisappear {
            sessionManager.pause()
        }
    }

    public init() {}

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                strokeRecorder.clear()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(.black.opacity(0.72))
            .disabled(strokeRecorder.samples.isEmpty)
            .accessibilityLabel("Clear stroke")

            Button {
                if strokeRecorder.isRecording {
                    strokeRecorder.end()
                } else {
                    strokeRecorder.begin()
                }
            } label: {
                Label(
                    strokeRecorder.isRecording ? "End Stroke" : "Start Stroke",
                    systemImage: strokeRecorder.isRecording ? "stop.fill" : "record.circle"
                )
                .font(.system(.headline, design: .rounded))
                .frame(minWidth: 156, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(strokeRecorder.isRecording ? .red : .white)
            .foregroundStyle(strokeRecorder.isRecording ? .white : .black)
        }
    }

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

            Text("stroke samples: \(strokeRecorder.samples.count)")
            Text("section samples: \(strokeRecorder.samples.filter { $0.brushSectionImage != nil }.count)")
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AR tracking debug information")
    }
}
