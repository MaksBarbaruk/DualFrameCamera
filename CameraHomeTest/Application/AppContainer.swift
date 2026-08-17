import Foundation

struct AppContainer: Sendable {
    let captureRepository: any CaptureRepository
    let cameraCaptureClient: any CameraCaptureClient

    static func live() -> AppContainer {
        AppContainer(
            captureRepository: InMemoryCaptureRepository(),
            cameraCaptureClient: UnavailableCameraCaptureClient()
        )
    }
}
