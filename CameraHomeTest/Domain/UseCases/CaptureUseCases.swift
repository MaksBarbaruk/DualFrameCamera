import Foundation

struct LoadCaptureFeedUseCase: Sendable {
    let repository: any CaptureRepository

    func callAsFunction() async throws -> [CapturePair] {
        try await repository.captures()
            .sorted { $0.createdAt > $1.createdAt }
    }
}

struct LoadCaptureDetailUseCase: Sendable {
    let repository: any CaptureRepository

    func callAsFunction(id: UUID) async throws -> CapturePair? {
        try await repository.capture(id: id)
    }
}

struct DeleteCaptureUseCase: Sendable {
    let repository: any CaptureRepository

    func callAsFunction(id: UUID) async throws {
        try await repository.delete(id: id)
    }
}

