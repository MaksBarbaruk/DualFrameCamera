import Foundation

protocol CaptureRepository: Sendable {
    func captures() async throws -> [CapturePair]
    func capture(id: UUID) async throws -> CapturePair?
    func save(_ capture: CapturePair) async throws
    func delete(id: UUID) async throws
}

