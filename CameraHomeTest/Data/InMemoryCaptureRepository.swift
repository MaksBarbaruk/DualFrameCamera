import Foundation

actor InMemoryCaptureRepository: CaptureRepository {
    private var storage: [UUID: CapturePair] = [:]

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

