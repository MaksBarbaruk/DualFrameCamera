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

    func save(_ capture: CapturePair) {
        storage[capture.id] = capture
    }

    func delete(id: UUID) {
        storage[id] = nil
    }
}
