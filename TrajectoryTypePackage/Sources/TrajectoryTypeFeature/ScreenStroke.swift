import Foundation

public struct ScreenStroke: Identifiable {
    public let id: UUID
    public let samples: [ScreenStrokeSample]

    public init(id: UUID = UUID(), samples: [ScreenStrokeSample]) {
        self.id = id
        self.samples = samples
    }
}
