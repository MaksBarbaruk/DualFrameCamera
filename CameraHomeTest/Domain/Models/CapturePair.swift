import Foundation

nonisolated struct CaptureAsset: Codable, Hashable, Sendable {
    enum Position: String, Codable, Sendable {
        case rear
        case front
    }

    let position: Position
    let fileURL: URL
    let pixelWidth: Int
    let pixelHeight: Int
    let capturedAt: Date
    let captureUptimeNanoseconds: UInt64
}

nonisolated struct CapturePair: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let rear: CaptureAsset
    let front: CaptureAsset

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        rear: CaptureAsset,
        front: CaptureAsset
    ) {
        self.id = id
        self.createdAt = createdAt
        self.rear = rear
        self.front = front
    }
}
