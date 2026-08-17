import Foundation

struct AppContainer: Sendable {
    let captureRepository: any CaptureRepository

    static func live() -> AppContainer {
        AppContainer(captureRepository: InMemoryCaptureRepository())
    }
}

