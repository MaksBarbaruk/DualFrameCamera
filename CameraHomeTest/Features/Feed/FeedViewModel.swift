import Foundation
import Observation

@MainActor
@Observable
final class FeedViewModel {
    private let loadFeed: LoadCaptureFeedUseCase

    private(set) var captures: [CapturePair] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init(repository: any CaptureRepository) {
        loadFeed = LoadCaptureFeedUseCase(repository: repository)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            captures = try await loadFeed()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

