import SwiftUI

struct BrushDragGuideView: View {
    let configuration: BrushDragConfiguration

    var body: some View {
        ZStack {
            Path { path in
                path.move(to: configuration.startPoint)
                path.addLine(to: configuration.endPoint)
            }
            .stroke(.white.opacity(0.92), style: StrokeStyle(lineWidth: 2, lineCap: .round))

            Circle()
                .fill(.white)
                .frame(width: 10, height: 10)
                .position(configuration.startPoint)

            Circle()
                .fill(.black.opacity(0.42))
                .stroke(.white.opacity(0.92), lineWidth: 2)
                .frame(width: 16, height: 16)
                .position(configuration.endPoint)
        }
        .accessibilityHidden(true)
    }
}
