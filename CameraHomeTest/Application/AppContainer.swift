import Foundation

struct AppContainer: Sendable {
    let captureRepository: any CaptureRepository
    let cameraCaptureClient: any CameraCaptureClient
    let cameraPreviewSource: any CameraPreviewSource

    static func live() -> AppContainer {
        let camera = MultiCamCaptureEngine()
        return AppContainer(
            captureRepository: InMemoryCaptureRepository(),
            cameraCaptureClient: camera,
            cameraPreviewSource: camera
        )
    }
}
