import Foundation
import SwiftUI

@MainActor
public struct ContentView: View {
    @State private var cameraManager = CameraSessionManager()
    @State private var strokeRecorder = ScreenStrokeRecorder()
    @State private var brushWidthPoints: CGFloat = 34
    @State private var brushAngleRadians: CGFloat = 0

    public var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .bottomLeading) {
                CameraPreviewContainer(session: cameraManager.session)
                    .ignoresSafeArea()

                Color.black
                    .ignoresSafeArea()
                    .opacity(strokeRecorder.isRecording ? 0.68 : 0)
                    .animation(.easeOut(duration: 0.16), value: strokeRecorder.isRecording)
                    .allowsHitTesting(false)

                StrokeCanvasView(strokes: strokeRecorder.displayStrokes)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                StrokeTouchSurface(
                    onDragBegan: { point, size in
                        beginStroke(at: point, in: size)
                    },
                    onDragMoved: { point, size in
                        recordStroke(at: point, in: size)
                    },
                    onDragEnded: { point, size in
                        recordStroke(at: point, in: size)
                        strokeRecorder.end()
                    },
                    onDragCancelled: {
                        strokeRecorder.end()
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
        }
        .onAppear {
            cameraManager.start()
        }
        .onDisappear {
            cameraManager.stop()
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
            Text(cameraManager.captureDescription)
                .font(.system(.footnote, design: .rounded))

            Text(strokeRecorder.isRecording ? "recording: on" : "recording: off")
            Text("strokes: \(strokeRecorder.strokes.count)")
            Text("stroke samples: \(strokeRecorder.sampleCount)")
            Text("section samples: \(strokeRecorder.brushSectionSampleCount)")
            Text("brush: \(Int(brushWidthPoints.rounded()))pt \(Int((brushAngleRadians * 180 / .pi).rounded()))°")
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Camera stroke debug information")
    }

    private func beginStroke(at point: CGPoint, in size: CGSize) {
        strokeRecorder.begin(
            at: point,
            in: size,
            brushAngleRadians: brushAngleRadians
        )
        recordStroke(at: point, in: size)
    }

    private func recordStroke(at point: CGPoint, in size: CGSize) {
        strokeRecorder.record(
            point: point,
            in: size,
            brushWidth: brushWidthPoints
        ) { brushAngleRadians, normalizedSamplePoint in
            cameraManager.makeLiveBrushSection(
                angleRadians: brushAngleRadians,
                normalizedPreviewPoint: normalizedSamplePoint,
                previewSize: size,
                brushWidthPoints: brushWidthPoints
            )
        }
        brushAngleRadians = strokeRecorder.currentBrushAngleRadians
    }
}
