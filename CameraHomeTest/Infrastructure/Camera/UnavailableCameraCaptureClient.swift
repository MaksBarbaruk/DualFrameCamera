import Foundation

actor UnavailableCameraCaptureClient: CameraCaptureClient {
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
}

