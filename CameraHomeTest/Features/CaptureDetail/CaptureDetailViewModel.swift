import Foundation
import Observation

@MainActor
@Observable
final class CaptureDetailViewModel {
    private let captureID: UUID
    private let loadDetail: LoadCaptureDetailUseCase

    private(set) var capture: CapturePair?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var showsFrontAsPrimary = false

    init(captureID: UUID, repository: any CaptureRepository) {
        self.captureID = captureID
        loadDetail = LoadCaptureDetailUseCase(repository: repository)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            capture = try await loadDetail(id: captureID)
            errorMessage = capture == nil ? "This moment is no longer available." : nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func swapPrimaryImage() {
        showsFrontAsPrimary.toggle()
    }
}

