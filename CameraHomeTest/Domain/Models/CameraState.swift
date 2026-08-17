import Foundation

nonisolated enum CameraAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

nonisolated enum CameraCapability: Equatable, Sendable {
    case available
    case simulator
    case multiCamUnavailable
    case supportedPairUnavailable
}

nonisolated enum CameraPressureLevel: Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical
    case shutdown
}

nonisolated enum CameraCapturePhase: Equatable, Sendable {
    case rearCaptured
    case waitingForFront
    case frontCaptured
    case encoding
}

nonisolated enum CameraSessionEvent: Equatable, Sendable {
    case running
    case stopped
    case interrupted(message: String)
    case interruptionEnded
    case pressureChanged(CameraPressureLevel)
    case runtimeError(message: String, recovered: Bool)
    case capturePhase(CameraCapturePhase)
}

nonisolated enum CameraCaptureState: Equatable, Sendable {
    case idle
    case requestingPermission
    case starting
    case ready
    case capturingRear
    case waitingForFront(progress: Double)
    case capturingFront
    case saving
    case interrupted(message: String)
    case failed(message: String)

    var allowsCapture: Bool {
        self == .ready
    }
}

nonisolated enum CameraCaptureError: LocalizedError, Equatable, Sendable {
    case permissionDenied
    case permissionRestricted
    case multiCamUnsupported
    case supportedPairUnavailable
    case sessionNotReady
    case captureInProgress
    case incompleteCapture
    case sessionInterrupted(String)
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Camera access is disabled. Enable it in Settings to take a paired photo."
        case .permissionRestricted:
            "Camera access is restricted on this device."
        case .multiCamUnsupported:
            "This device does not support simultaneous front and rear camera capture."
        case .supportedPairUnavailable:
            "A compatible front and rear camera pair is not available."
        case .sessionNotReady:
            "The camera is not ready yet."
        case .captureInProgress:
            "A paired capture is already in progress."
        case .incompleteCapture:
            "Both images could not be captured. Please try again."
        case .sessionInterrupted(let message):
            message
        case .underlying(let message):
            message
        }
    }
}
