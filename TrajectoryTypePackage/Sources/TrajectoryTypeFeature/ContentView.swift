import Foundation
import SwiftUI

@MainActor
public struct ContentView: View {
    @State private var sessionManager = ARSessionManager()
    @State private var strokeRecorder = ScreenStrokeRecorder()
    @State private var brushWidthPixels = 34
    @State private var brushAngleRadians: CGFloat = 0

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                ARViewContainer(sessionManager: sessionManager)
                    .ignoresSafeArea()
                    .opacity(strokeRecorder.isRecording ? 0 : 1)

                Color.black
                    .ignoresSafeArea()
                    .opacity(strokeRecorder.isRecording ? 1 : 0)

                StrokeCanvasView(strokes: strokeRecorder.displayStrokes)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                StrokeTouchSurface { point, size in
                    if strokeRecorder.isRecording {
                        strokeRecorder.end()
                    } else {
                        sessionManager.brushAngleRadians = brushAngleRadians
                        strokeRecorder.begin(at: point, in: size, pose: sessionManager.latestPose)
                    }
                }
                .ignoresSafeArea()

                controls
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 28)

                debugOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading)
                    .padding(.top, 16)
                    .allowsHitTesting(false)
            }
            .onChange(of: sessionManager.latestPose?.timestamp) {
                guard let pose = sessionManager.latestPose else {
                    return
                }

                sessionManager.brushAngleRadians = brushAngleRadians
                strokeRecorder.record(
                    pose: pose,
                    in: proxy.size,
                    brushWidth: CGFloat(brushWidthPixels),
                    brushAngleRadians: brushAngleRadians
                ) {
                    sessionManager.latestBrushSection
                }
            }
            .onChange(of: brushAngleRadians) {
                sessionManager.brushAngleRadians = brushAngleRadians
            }
        }
        .onAppear {
            sessionManager.brushAngleRadians = brushAngleRadians
            sessionManager.start()
        }
        .onDisappear {
            sessionManager.pause()
        }
    }

    public init() {}

    private var controls: some View {
        HStack(alignment: .bottom) {
            RotaryBrushControl(widthPixels: $brushWidthPixels, angleRadians: $brushAngleRadians)

            Spacer()

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
                .disabled(strokeRecorder.sampleCount == 0)
                .accessibilityLabel("Clear stroke")
            }
        }
        .padding(.horizontal, 18)
    }

    private var debugOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sessionManager.trackingDescription)
                .font(.system(.footnote, design: .rounded))

            Text(strokeRecorder.isRecording ? "recording: on" : "recording: off")
            Text("strokes: \(strokeRecorder.strokes.count)")
            Text("stroke samples: \(strokeRecorder.sampleCount)")
            Text("section samples: \(strokeRecorder.brushSectionSampleCount)")
            Text("brush: \(brushWidthPixels)px \(Int(RotaryBrushControl.degrees(from: brushAngleRadians).rounded()))°")
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AR tracking debug information")
    }
}
