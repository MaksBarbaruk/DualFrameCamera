import Foundation
import Observation

@MainActor
@Observable
final class CameraViewModel {
    private let cameraClient: any CameraCaptureClient

    private(set) var state: CameraCaptureState = .idle
    private(set) var capability: CameraCapability?
    private(set) var supportTitle = "Preparing cameras"
    private(set) var supportMessage = "Checking this device for simultaneous front and rear capture."

    init(cameraClient: any CameraCaptureClient) {
        self.cameraClient = cameraClient
    }

    var isCaptureEnabled: Bool {
        state.allowsCapture
    }

    var showsSupportCard: Bool {
        capability != .available
    }

    var frontCaptureProgress: Double? {
        guard case .waitingForFront(let progress) = state else { return nil }
        return min(max(progress, 0), 1)
    }

    var statusText: String {
        switch state {
        case .idle: "Preview mode"
        case .requestingPermission: "Requesting access"
        case .starting: "Starting cameras"
        case .ready: "Both cameras ready"
        case .capturingRear: "Rear captured"
        case .waitingForFront: "Hold steady"
        case .capturingFront: "Front captured"
        case .saving: "Saving moment"
        case .interrupted: "Camera paused"
        case .failed: "Camera unavailable"
        }
    }

    func prepare() async {
        state = .starting
        let capability = await cameraClient.capability()
        self.capability = capability

        switch capability {
        case .simulator:
            supportTitle = "Interface preview"
            supportMessage = "Connect a MultiCam-capable iPhone to replace this designed preview with both live cameras."
            state = .idle
            return
        case .multiCamUnavailable:
            supportTitle = "MultiCam unavailable"
            supportMessage = CameraCaptureError.multiCamUnsupported.localizedDescription
            state = .failed(message: supportMessage)
            return
        case .supportedPairUnavailable:
            supportTitle = "Camera pair unavailable"
            supportMessage = CameraCaptureError.supportedPairUnavailable.localizedDescription
            state = .failed(message: supportMessage)
            return
        case .available:
            break
        }

        var authorization = await cameraClient.authorizationStatus()
        if authorization == .notDetermined {
            state = .requestingPermission
            authorization = await cameraClient.requestAuthorization()
        }

        switch authorization {
        case .authorized:
            break
        case .denied:
            supportTitle = "Camera access needed"
            supportMessage = CameraCaptureError.permissionDenied.localizedDescription
            state = .failed(message: supportMessage)
            return
        case .restricted:
            supportTitle = "Camera access restricted"
            supportMessage = CameraCaptureError.permissionRestricted.localizedDescription
            state = .failed(message: supportMessage)
            return
        case .notDetermined:
            return
        }

        do {
            state = .starting
            try await cameraClient.start()
            state = .ready
        } catch {
            supportTitle = "Unable to start cameras"
            supportMessage = error.localizedDescription
            state = .failed(message: supportMessage)
        }
    }

    func capture() async {
        guard isCaptureEnabled else { return }

        state = .capturingRear
        do {
            _ = try await cameraClient.capturePair()
            state = .ready
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    func stop() {
        Task {
            await cameraClient.stop()
        }
    }
}
