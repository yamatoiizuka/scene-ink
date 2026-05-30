import CoreGraphics
import Foundation
import Testing
@testable import TrajectoryTypeFeature

@MainActor
@Test func screenStrokeRecorderRecordsTouchDragSamples() async throws {
    let recorder = ScreenStrokeRecorder()
    let viewportSize = CGSize(width: 400, height: 800)

    recorder.begin(
        at: CGPoint(x: 100, y: 200),
        in: viewportSize,
        brushAngleRadians: 0
    )
    recorder.record(
        point: CGPoint(x: 100, y: 200),
        in: viewportSize,
        brushWidth: 12,
        timestamp: 1
    )
    recorder.record(
        point: CGPoint(x: 130, y: 230),
        in: viewportSize,
        brushWidth: 12,
        timestamp: 2
    )

    #expect(recorder.activeSamples.count == 2)
    #expect(abs(recorder.activeSamples[0].normalizedPoint.x - 0.25) < 0.000_1)
    #expect(abs(recorder.activeSamples[0].normalizedPoint.y - 0.25) < 0.000_1)
    #expect(abs(recorder.activeSamples[1].normalizedPoint.x - 0.325) < 0.000_1)
    #expect(abs(recorder.activeSamples[1].normalizedPoint.y - 0.287_5) < 0.000_1)
}

@Test func screenStrokeRecorderUsesDragDirectionForBrushAngle() async throws {
    let verticalDown = ScreenStrokeRecorder.brushAngle(
        forDragFrom: CGPoint(x: 100, y: 100),
        to: CGPoint(x: 100, y: 150)
    )
    let horizontalRight = ScreenStrokeRecorder.brushAngle(
        forDragFrom: CGPoint(x: 100, y: 100),
        to: CGPoint(x: 150, y: 100)
    )

    #expect(abs(verticalDown) < 0.000_1)
    #expect(abs(horizontalRight - (.pi / 2)) < 0.000_1)
}

@MainActor
@Test func screenStrokeRecorderRequestsBrushSectionOnlyWhenAppendingSample() async throws {
    let recorder = ScreenStrokeRecorder()
    let viewportSize = CGSize(width: 400, height: 800)
    var sectionRequestCount = 0

    recorder.begin(
        at: CGPoint(x: 200, y: 400),
        in: viewportSize,
        brushAngleRadians: 0
    )
    recorder.record(
        point: CGPoint(x: 200, y: 400),
        in: viewportSize,
        brushWidth: 12
    ) { _, _ in
        sectionRequestCount += 1
        return nil
    }
    recorder.record(
        point: CGPoint(x: 200, y: 400),
        in: viewportSize,
        brushWidth: 12
    ) { _, _ in
        sectionRequestCount += 1
        return nil
    }

    #expect(recorder.activeSamples.count == 1)
    #expect(sectionRequestCount == 1)
}

@Test func frameCaptureMapsTapPointIntoCameraImageCoordinates() async throws {
    let sourceExtent = CGRect(x: 0, y: 0, width: 100, height: 200)

    let topLeft = FrameCapture.sourcePoint(
        in: sourceExtent,
        normalizedPreviewPoint: CGPoint(x: 0, y: 0)
    )
    let center = FrameCapture.sourcePoint(
        in: sourceExtent,
        normalizedPreviewPoint: CGPoint(x: 0.5, y: 0.5)
    )

    #expect(abs(topLeft.x) < 0.000_1)
    #expect(abs(topLeft.y - 200) < 0.000_1)
    #expect(abs(center.x - 50) < 0.000_1)
    #expect(abs(center.y - 100) < 0.000_1)
}

@Test func frameCaptureAccountsForAspectFillPreviewCropping() async throws {
    let sourceExtent = CGRect(x: 0, y: 0, width: 200, height: 100)

    let leftCenter = FrameCapture.sourcePoint(
        in: sourceExtent,
        normalizedPreviewPoint: CGPoint(x: 0, y: 0.5),
        previewSize: CGSize(width: 100, height: 100)
    )
    let rightCenter = FrameCapture.sourcePoint(
        in: sourceExtent,
        normalizedPreviewPoint: CGPoint(x: 1, y: 0.5),
        previewSize: CGSize(width: 100, height: 100)
    )

    #expect(abs(leftCenter.x - 50) < 0.000_1)
    #expect(abs(leftCenter.y - 50) < 0.000_1)
    #expect(abs(rightCenter.x - 150) < 0.000_1)
    #expect(abs(rightCenter.y - 50) < 0.000_1)
}

@Test func frameCaptureMapsScreenLineLengthToVisibleCameraPixels() async throws {
    let sourceExtent = CGRect(x: 0, y: 0, width: 1200, height: 1600)
    let previewSize = CGSize(width: 390, height: 844)
    let sourceLength = FrameCapture.sourceLineLengthPixels(
        forScreenLength: 34,
        in: sourceExtent,
        previewSize: previewSize
    )
    let visibleSourceWidth = previewSize.width / previewSize.height * sourceExtent.height
    let expectedLength = 34 * (visibleSourceWidth / previewSize.width)

    #expect(abs(sourceLength - expectedLength) < 0.000_1)
    #expect(sourceLength < 100)
}

@Test func frameCaptureSamplesBrushSectionFromCGImage() async throws {
    let sourceImage = try #require(makeTestImage(width: 12, height: 16))
    let sectionImage = FrameCapture().makeBrushSection(
        from: sourceImage,
        angleRadians: 0,
        outputSize: CGSize(width: 1, height: 12)
    )

    #expect(sectionImage?.width == 1)
    #expect(sectionImage?.height == 12)
}

@Test func frameCaptureLimitsSamplingBoundsToLinePatch() async throws {
    let sourceExtent = CGRect(x: 0, y: 0, width: 2000, height: 1500)
    let bounds = FrameCapture.lineSamplingBounds(
        center: CGPoint(x: 1000, y: 750),
        brushAngleRadians: 0,
        lineLengthPixels: 640,
        lineWidthPixels: 1,
        sourceExtent: sourceExtent
    )

    #expect(bounds.width < sourceExtent.width / 2)
    #expect(bounds.height < 20)
    #expect(bounds.contains(CGPoint(x: 1000, y: 750)))
}

@MainActor
@Test func endingRecorderCommitsActiveStrokeInDrawOrder() async throws {
    let recorder = ScreenStrokeRecorder()
    let viewportSize = CGSize(width: 400, height: 800)

    recorder.begin(
        at: CGPoint(x: 120, y: 300),
        in: viewportSize,
        brushAngleRadians: 0
    )
    recorder.record(
        point: CGPoint(x: 120, y: 300),
        in: viewportSize,
        brushWidth: 12
    )
    recorder.record(
        point: CGPoint(x: 150, y: 330),
        in: viewportSize,
        brushWidth: 12
    )
    recorder.end()

    #expect(recorder.strokes.count == 1)
    #expect(recorder.activeSamples.isEmpty)
    #expect(recorder.displayStrokes.map(\.id) == recorder.strokes.map(\.id))
}

@MainActor
@Test func undoLastStrokeRemovesMostRecentCommittedStroke() async throws {
    let recorder = ScreenStrokeRecorder()
    let viewportSize = CGSize(width: 400, height: 800)

    for index in 0..<2 {
        let offset = CGFloat(index * 30)
        recorder.begin(
            at: CGPoint(x: 120 + offset, y: 300),
            in: viewportSize,
            brushAngleRadians: 0
        )
        recorder.record(
            point: CGPoint(x: 120 + offset, y: 300),
            in: viewportSize,
            brushWidth: 12
        )
        recorder.record(
            point: CGPoint(x: 150 + offset, y: 330),
            in: viewportSize,
            brushWidth: 12
        )
        recorder.end()
    }

    let firstStrokeID = recorder.strokes[0].id
    let secondStrokeID = recorder.strokes[1].id

    recorder.undoLastStroke()

    #expect(recorder.strokes.count == 1)
    #expect(recorder.strokes[0].id == firstStrokeID)
    #expect(recorder.strokes.contains { $0.id == secondStrokeID } == false)
}

private func makeTestImage(width: Int, height: Int) -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }

    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}
