import Foundation
import Observation

@MainActor
@Observable
final class CameraViewModel {
    private let cameraClient: any CameraCaptureClient
    private let persistCapture: PersistCapturePairUseCase
    private var eventTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var activeTorchOperationID: UUID?

    private(set) var state: CameraCaptureState = .idle
    private(set) var capability: CameraCapability?
    private(set) var isTorchAvailable = false
    private(set) var isTorchEnabled = false
    private(set) var isTorchChanging = false
    private(set) var supportTitle = "Preparing cameras"
    private(set) var supportMessage = "Checking this device for simultaneous front and rear capture."

    init(
        cameraClient: any CameraCaptureClient,
        repository: any CaptureRepository
    ) {
        self.cameraClient = cameraClient
        persistCapture = PersistCapturePairUseCase(repository: repository)
    }

    var isCaptureEnabled: Bool {
        state.allowsCapture
    }

    var showsSupportCard: Bool {
        guard capability == .available else { return true }
        switch state {
        case .failed, .interrupted:
            return true
        default:
            return false
        }
    }

    var canRetry: Bool {
        if case .failed = state { return true }
        return false
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
        if let stopTask {
            await stopTask.value
            self.stopTask = nil
        }
        resetTorchPresentation()
        startObservingEvents()
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
            await refreshTorchAvailability()
            state = .ready
        } catch is CancellationError {
            progressTask?.cancel()
            switch state {
            case .failed, .interrupted:
                break
            default:
                state = .idle
            }
            return
        } catch {
            supportTitle = "Unable to start cameras"
            supportMessage = error.localizedDescription
            state = .failed(message: supportMessage)
        }
    }

    func toggleTorch() async throws {
        guard state == .ready, isTorchAvailable, !isTorchChanging else {
            throw CameraCaptureError.torchUnavailable
        }

        let operationID = UUID()
        activeTorchOperationID = operationID
        isTorchChanging = true
        defer {
            if activeTorchOperationID == operationID {
                activeTorchOperationID = nil
                isTorchChanging = false
            }
        }

        let shouldEnable = !isTorchEnabled
        try await cameraClient.setTorchEnabled(shouldEnable)
        guard activeTorchOperationID == operationID else { return }
        isTorchEnabled = shouldEnable
    }

    func capture() async -> CapturePair? {
        guard isCaptureEnabled else { return nil }

        state = .capturingRear
        do {
            let payload = try await cameraClient.capturePair()
            state = .saving
            let capture = try await persistCapture(payload)
            state = .ready
            return capture
        } catch is CancellationError {
            progressTask?.cancel()
            switch state {
            case .failed, .interrupted:
                break
            default:
                state = .idle
            }
            return nil
        } catch {
            supportTitle = "Capture failed"
            supportMessage = error.localizedDescription
            state = .failed(message: error.localizedDescription)
            return nil
        }
    }

    func stop() {
        eventTask?.cancel()
        eventTask = nil
        progressTask?.cancel()
        progressTask = nil
        resetTorchPresentation()
        let previousStopTask = stopTask
        stopTask = Task {
            await previousStopTask?.value
            await cameraClient.stop()
        }
    }

    func retry() async {
        await cameraClient.stop()
        await prepare()
    }

    private func startObservingEvents() {
        eventTask?.cancel()
        eventTask = Task { [weak self, cameraClient] in
            let events = await cameraClient.sessionEvents()
            for await event in events {
                guard !Task.isCancelled else { return }
                self?.handle(event)
            }
        }
    }

    private func handle(_ event: CameraSessionEvent) {
        switch event {
        case .running:
            state = .ready
            Task { [weak self] in
                await self?.refreshTorchAvailability()
            }
        case .stopped:
            resetTorchPresentation()
            if capability == .available {
                state = .idle
            }
        case .interrupted(let message):
            progressTask?.cancel()
            resetTorchPresentation()
            supportTitle = "Camera paused"
            supportMessage = message
            state = .interrupted(message: message)
        case .interruptionEnded:
            state = .starting
        case .pressureChanged(let level):
            if level == .shutdown {
                resetTorchPresentation()
                state = .interrupted(message: "The cameras paused because the device needs to cool down.")
            }
        case .runtimeError(let message, let recovered):
            resetTorchPresentation()
            supportTitle = recovered ? "Camera recovered" : "Camera error"
            supportMessage = message
            state = recovered ? .ready : .failed(message: message)
        case .capturePhase(let phase):
            handle(phase)
        }
    }

    private func handle(_ phase: CameraCapturePhase) {
        switch phase {
        case .rearCaptured:
            state = .capturingRear
        case .waitingForFront:
            beginFrontProgress()
        case .frontCaptured:
            progressTask?.cancel()
            state = .capturingFront
        case .encoding:
            state = .saving
        }
    }

    private func beginFrontProgress() {
        progressTask?.cancel()
        state = .waitingForFront(progress: 0)
        progressTask = Task { [weak self] in
            let steps = 30
            for step in 1...steps {
                try? await Task<Never, Never>.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled else { return }
                self?.state = .waitingForFront(progress: Double(step) / Double(steps))
            }
        }
    }

    private func refreshTorchAvailability() async {
        isTorchAvailable = await cameraClient.isTorchAvailable()
    }

    private func resetTorchPresentation() {
        activeTorchOperationID = nil
        isTorchAvailable = false
        isTorchEnabled = false
        isTorchChanging = false
    }
}
