import Foundation
import SwiftUI

@MainActor
public struct ContentView: View {
    @State private var sessionManager = ARSessionManager()
    @State private var strokeRecorder = ScreenStrokeRecorder()
    @State private var brushWidthPoints: CGFloat = 34
    @State private var brushAngleRadians: CGFloat = 0
    @State private var pendingBrushConfiguration: BrushDragConfiguration?

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

                if let pendingBrushConfiguration, !strokeRecorder.isRecording {
                    BrushDragGuideView(configuration: pendingBrushConfiguration)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                StrokeTouchSurface(
                    onDragChanged: { configuration, size in
                        guard !strokeRecorder.isRecording else {
                            return
                        }

                        pendingBrushConfiguration = configuration
                        applyBrushConfiguration(configuration, in: size)
                    },
                    onDragEnded: { configuration, size in
                        pendingBrushConfiguration = nil

                        if strokeRecorder.isRecording {
                            strokeRecorder.end()
                            sessionManager.clearStrokeSourceImage()
                            return
                        }

                        guard configuration.isDrawable else {
                            return
                        }

                        applyBrushConfiguration(configuration, in: size)
                        sessionManager.captureStrokeSourceImage()
                        strokeRecorder.begin(
                            at: configuration.startPoint,
                            in: size,
                            pose: sessionManager.latestPose,
                            brushAngleRadians: brushAngleRadians
                        )
                    },
                    onDragCancelled: {
                        pendingBrushConfiguration = nil
                    }
                )
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
                guard strokeRecorder.isRecording, let pose = sessionManager.latestPose else {
                    return
                }

                strokeRecorder.record(
                    pose: pose,
                    in: proxy.size,
                    brushWidth: brushWidthPoints
                ) { brushAngleRadians, normalizedSamplePoint in
                    sessionManager.makeBrushSection(
                        angleRadians: brushAngleRadians,
                        normalizedPreviewPoint: normalizedSamplePoint
                    )
                }
                brushAngleRadians = strokeRecorder.currentBrushAngleRadians
                sessionManager.brushAngleRadians = strokeRecorder.currentBrushAngleRadians
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
            sessionManager.clearStrokeSourceImage()
            sessionManager.pause()
        }
    }

    public init() {}

    private var controls: some View {
        HStack {
            Spacer()

            VStack(spacing: 10) {
                Button {
                    strokeRecorder.undoLastStroke()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(.black.opacity(0.72))
                .disabled(strokeRecorder.strokes.isEmpty)
                .accessibilityLabel("Undo last stroke")

                Button {
                    strokeRecorder.clear()
                    sessionManager.clearStrokeSourceImage()
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
            Text("source: \(sessionManager.hasStrokeSourceImage ? "fixed" : "live")")
            Text("brush: \(Int(brushWidthPoints.rounded()))pt \(Int(BrushDragConfiguration.degrees(from: brushAngleRadians).rounded()))°")
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AR tracking debug information")
    }

    private func applyBrushConfiguration(_ configuration: BrushDragConfiguration, in size: CGSize) {
        brushWidthPoints = max(configuration.width, BrushDragConfiguration.minimumDrawableWidth)
        brushAngleRadians = configuration.angleRadians
        sessionManager.brushAngleRadians = configuration.angleRadians
        sessionManager.setBrushSamplePoint(configuration.startPoint, in: size)
    }
}
