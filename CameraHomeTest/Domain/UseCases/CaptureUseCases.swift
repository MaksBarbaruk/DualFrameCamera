import Foundation

nonisolated struct PersistCapturePairUseCase: Sendable {
    let repository: any CaptureRepository

    func callAsFunction(_ payload: CapturedPairPayload) async throws -> CapturePair {
        try await repository.save(payload)
    }
}

nonisolated struct LoadCaptureFeedUseCase: Sendable {
    let repository: any CaptureRepository

    func callAsFunction() async throws -> [CapturePair] {
        try await repository.captures()
            .sorted { $0.createdAt > $1.createdAt }
    }
}

nonisolated struct LoadCaptureDetailUseCase: Sendable {
    let repository: any CaptureRepository

    func callAsFunction(id: UUID) async throws -> CapturePair? {
        try await repository.capture(id: id)
    }
}

nonisolated struct DeleteCaptureUseCase: Sendable {
    let repository: any CaptureRepository

    func callAsFunction(id: UUID) async throws {
        try await repository.delete(id: id)
    }
}
