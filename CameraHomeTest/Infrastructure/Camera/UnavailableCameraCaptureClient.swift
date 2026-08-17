@preconcurrency import AVFoundation
import Foundation

nonisolated final class UnavailableCameraCaptureClient: CameraCaptureClient, CameraPreviewSource, @unchecked Sendable {
    func authorizationStatus() -> CameraAuthorization {
        .notDetermined
    }

    func requestAuthorization() -> CameraAuthorization {
        .notDetermined
    }

    func capability() -> CameraCapability {
#if targetEnvironment(simulator)
        .simulator
#else
        .multiCamUnavailable
#endif
    }

    func start() throws {
        throw CameraCaptureError.multiCamUnsupported
    }

    func stop() { }

    func capturePair() throws -> CapturedPairPayload {
        throw CameraCaptureError.sessionNotReady
    }

    func sessionEvents() -> AsyncStream<CameraSessionEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func attachPreviewLayer(
        _ layer: AVCaptureVideoPreviewLayer,
        position: CaptureAsset.Position
    ) { }

    func detachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) { }
}
