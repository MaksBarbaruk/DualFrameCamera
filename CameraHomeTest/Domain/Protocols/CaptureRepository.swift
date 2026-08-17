import Foundation

nonisolated protocol CaptureRepository: Sendable {
    func captures() async throws -> [CapturePair]
    func capture(id: UUID) async throws -> CapturePair?
    func save(_ payload: CapturedPairPayload) async throws -> CapturePair
    func delete(id: UUID) async throws
}
