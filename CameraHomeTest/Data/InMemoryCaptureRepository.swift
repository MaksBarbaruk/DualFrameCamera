import Foundation

actor InMemoryCaptureRepository: CaptureRepository {
    private var storage: [UUID: CapturePair]

    init(captures: [CapturePair] = []) {
        storage = Dictionary(uniqueKeysWithValues: captures.map { ($0.id, $0) })
    }

    func captures() -> [CapturePair] {
        Array(storage.values)
    }

    func capture(id: UUID) -> CapturePair? {
        storage[id]
    }

    func save(_ payload: CapturedPairPayload) -> CapturePair {
        let directory = URL(fileURLWithPath: "/memory/")
            .appendingPathComponent(payload.id.uuidString, isDirectory: true)
        let capture = CapturePair(
            id: payload.id,
            createdAt: payload.createdAt,
            rear: CaptureAsset(
                position: .rear,
                fileURL: directory.appendingPathComponent("rear.heic"),
                pixelWidth: payload.rear.pixelWidth,
                pixelHeight: payload.rear.pixelHeight,
                capturedAt: payload.rear.capturedAt,
                captureUptimeNanoseconds: payload.rear.captureUptimeNanoseconds
            ),
            front: CaptureAsset(
                position: .front,
                fileURL: directory.appendingPathComponent("front.heic"),
                pixelWidth: payload.front.pixelWidth,
                pixelHeight: payload.front.pixelHeight,
                capturedAt: payload.front.capturedAt,
                captureUptimeNanoseconds: payload.front.captureUptimeNanoseconds
            )
        )
        storage[capture.id] = capture
        return capture
    }

    func delete(id: UUID) {
        storage[id] = nil
    }
}
