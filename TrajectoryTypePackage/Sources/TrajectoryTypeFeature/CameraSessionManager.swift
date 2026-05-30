import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import Observation
@preconcurrency import AVFoundation

@MainActor
@Observable
public final class CameraSessionManager: NSObject {
    @ObservationIgnored
    nonisolated public let session: AVCaptureSession

    public private(set) var captureDescription = "Camera is not running."
    public private(set) var isRunning = false

    @ObservationIgnored
    private let frameCapture = FrameCapture()
    @ObservationIgnored
    private let videoOutput = AVCaptureVideoDataOutput()
    @ObservationIgnored
    private let sessionQueue = DispatchQueue(label: "TrajectoryType.CameraSession")
    @ObservationIgnored
    nonisolated private let frameStore = CameraFrameStore()

    private var isConfigured = false

    public override init() {
        self.session = AVCaptureSession()
        super.init()
    }

    public func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startAuthorizedSession()
        case .notDetermined:
            captureDescription = "Waiting for camera permission..."
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else {
                        return
                    }

                    if granted {
                        self.startAuthorizedSession()
                    } else {
                        self.isRunning = false
                        self.captureDescription = "Camera permission denied."
                    }
                }
            }
        case .denied, .restricted:
            isRunning = false
            captureDescription = "Camera permission denied."
        @unknown default:
            isRunning = false
            captureDescription = "Camera permission unavailable."
        }
    }

    public func stop() {
        let session = session
        sessionQueue.async { [weak self] in
            if session.isRunning {
                session.stopRunning()
            }

            Task { @MainActor in
                guard let self else {
                    return
                }

                self.isRunning = false
                self.captureDescription = "Camera stopped."
            }
        }
    }

    public func makeLiveBrushSection(
        angleRadians: CGFloat,
        normalizedPreviewPoint: CGPoint,
        previewSize: CGSize
    ) -> CGImage? {
        guard let pixelBuffer = frameStore.currentPixelBuffer() else {
            return nil
        }

        return frameCapture.makeBrushSection(
            from: pixelBuffer,
            angleRadians: angleRadians,
            normalizedPreviewPoint: normalizedPreviewPoint,
            previewSize: previewSize
        )
    }

    private func startAuthorizedSession() {
        do {
            try configureSessionIfNeeded()
        } catch {
            isRunning = false
            captureDescription = "Camera setup failed: \(error.localizedDescription)"
            return
        }

        captureDescription = "Starting camera..."
        let session = session
        sessionQueue.async { [weak self] in
            if !session.isRunning {
                session.startRunning()
            }

            let isRunning = session.isRunning
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.isRunning = isRunning
                self.captureDescription = isRunning ? "Camera running" : "Camera stopped."
            }
        }
    }

    private func configureSessionIfNeeded() throws {
        guard !isConfigured else {
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .high

        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video)
        else {
            session.commitConfiguration()
            throw CameraSessionError.noCamera
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraSessionError.cannotAddInput
        }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "TrajectoryType.CameraFrames"))

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            throw CameraSessionError.cannotAddOutput
        }
        session.addOutput(videoOutput)

        session.commitConfiguration()
        isConfigured = true
    }
}

extension CameraSessionManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        frameStore.set(pixelBuffer)
    }
}

private final class CameraFrameStore: @unchecked Sendable {
    private let lock = NSLock()
    private var pixelBuffer: CVPixelBuffer?

    func set(_ pixelBuffer: CVPixelBuffer) {
        lock.lock()
        self.pixelBuffer = pixelBuffer
        lock.unlock()
    }

    func currentPixelBuffer() -> CVPixelBuffer? {
        lock.lock()
        let pixelBuffer = pixelBuffer
        lock.unlock()
        return pixelBuffer
    }
}

private enum CameraSessionError: LocalizedError {
    case noCamera
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .noCamera:
            "No camera device is available."
        case .cannotAddInput:
            "Camera input could not be added."
        case .cannotAddOutput:
            "Camera output could not be added."
        }
    }
}
