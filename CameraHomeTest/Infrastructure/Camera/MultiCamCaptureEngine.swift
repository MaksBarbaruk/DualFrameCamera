@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import UIKit

nonisolated final class MultiCamCaptureEngine: CameraCaptureClient, CameraPreviewSource, @unchecked Sendable {
    private struct PreviewLayerReference: @unchecked Sendable {
        let value: AVCaptureVideoPreviewLayer
    }

    fileprivate struct DevicePair {
        let rear: AVCaptureDevice
        let front: AVCaptureDevice
    }

    private struct CaptureReservation: Sendable {
        let id: UUID
        let rearGeneration: UInt64
        let frontGeneration: UInt64
    }

    private let session = AVCaptureMultiCamSession()
    private let sessionQueue = DispatchQueue(label: "com.maksbarbaruk.dualcamera.session", qos: .userInitiated)
    private let rearOutputQueue = DispatchQueue(label: "com.maksbarbaruk.dualcamera.frames.rear", qos: .userInitiated)
    private let frontOutputQueue = DispatchQueue(label: "com.maksbarbaruk.dualcamera.frames.front", qos: .userInitiated)
    private let eventLock = NSLock()
    private let frameEncoder = PixelBufferEncoder()
    private let timingPolicy = CaptureTimingPolicy.standard
    private let rearCollector = VideoFrameCollector()
    private let frontCollector = VideoFrameCollector()

    private var isConfigured = false
    private var wantsToRun = false
    private var activeCaptureID: UUID?
    private var rearInput: AVCaptureDeviceInput?
    private var frontInput: AVCaptureDeviceInput?
    private var rearPort: AVCaptureInput.Port?
    private var frontPort: AVCaptureInput.Port?
    private var rearOutput: AVCaptureVideoDataOutput?
    private var frontOutput: AVCaptureVideoDataOutput?
    private var previewLayers: [CaptureAsset.Position: AVCaptureVideoPreviewLayer] = [:]
    private var previewConnections: [CaptureAsset.Position: AVCaptureConnection] = [:]
    private var notificationTokens: [NSObjectProtocol] = []
    private var pressureObservations: [NSKeyValueObservation] = []
    private var eventContinuations: [UUID: AsyncStream<CameraSessionEvent>.Continuation] = [:]

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        pressureObservations.forEach { $0.invalidate() }
        rearCollector.cancelAll()
        frontCollector.cancelAll()
    }

    func authorizationStatus() async -> CameraAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }

    func requestAuthorization() async -> CameraAuthorization {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .authorized : .denied
    }

    func capability() async -> CameraCapability {
#if targetEnvironment(simulator)
        return .simulator
#else
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            return .multiCamUnavailable
        }

        return await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: .supportedPairUnavailable)
                    return
                }
                continuation.resume(returning: self.discoverDevicePair() == nil ? .supportedPairUnavailable : .available)
            }
        }
#endif
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                do {
                    self.wantsToRun = true
                    if !self.isConfigured {
                        try self.configureSession()
                    }
                    self.installObserversIfNeeded()
                    if !self.session.isRunning {
                        self.session.startRunning()
                    }

                    guard self.session.isRunning else {
                        throw CameraCaptureError.underlying("The multi-camera session did not start.")
                    }

                    self.emit(.running)
                    continuation.resume()
                } catch {
                    self.wantsToRun = false
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                self.wantsToRun = false
                self.turnTorchOffIfNeeded()
                self.cancelPendingCapture()
                if self.session.isRunning {
                    self.session.stopRunning()
                }
                self.emit(.stopped)
                continuation.resume()
            }
        }
    }

    func isTorchAvailable() async -> Bool {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let device = self?.rearInput?.device else {
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(returning: self?.canUseTorch(on: device) == true)
            }
        }
    }

    func setTorchEnabled(_ enabled: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            sessionQueue.async { [weak self] in
                guard let self,
                      self.session.isRunning,
                      let device = self.rearInput?.device,
                      self.canUseTorch(on: device) else {
                    continuation.resume(throwing: CameraCaptureError.torchUnavailable)
                    return
                }

                do {
                    try device.lockForConfiguration()
                    defer { device.unlockForConfiguration() }
                    if enabled {
                        // A moderate level limits heat during sustained MultiCam use.
                        try device.setTorchModeOn(level: 0.5)
                    } else {
                        device.torchMode = .off
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(
                        throwing: CameraCaptureError.underlying(error.localizedDescription)
                    )
                }
            }
        }
    }

    func capturePair() async throws -> CapturedPairPayload {
        let reservation = try await reserveCapture()
        defer {
            sessionQueue.async { [weak self] in
                guard self?.activeCaptureID == reservation.id else { return }
                self?.activeCaptureID = nil
            }
        }

        let rearFrame = try await rearCollector.captureNextFrame(generation: reservation.rearGeneration)
        try await validateCapture(reservation.id, emitting: .rearCaptured)
        try await validateCapture(reservation.id, emitting: .waitingForFront)
        let remainingDelay = timingPolicy.remainingDelay(
            afterRearUptime: rearFrame.uptimeNanoseconds,
            currentUptime: DispatchTime.now().uptimeNanoseconds
        )
        if remainingDelay > 0 {
            try await Task<Never, Never>.sleep(nanoseconds: remainingDelay)
        }
        try await validateCapture(reservation.id)
        let frontFrame = try await frontCollector.captureNextFrame(generation: reservation.frontGeneration)
        try await validateCapture(reservation.id, emitting: .frontCaptured)

        let encoder = frameEncoder
        try await validateCapture(reservation.id, emitting: .encoding)
        let (rearPayload, frontPayload) = try await Task.detached(priority: .userInitiated) {
            (
                try encoder.encodeHEIF(rearFrame),
                try encoder.encodeHEIF(frontFrame)
            )
        }.value
        try await validateCapture(reservation.id)

        return CapturedPairPayload(
            id: UUID(),
            createdAt: rearPayload.capturedAt,
            rear: rearPayload,
            front: frontPayload
        )
    }

    func sessionEvents() async -> AsyncStream<CameraSessionEvent> {
        let id = UUID()

        return AsyncStream { continuation in
            eventLock.synchronized {
                eventContinuations[id] = continuation
            }

            continuation.onTermination = { [weak self] _ in
                self?.eventLock.synchronized {
                    self?.eventContinuations[id] = nil
                }
            }
        }
    }

    func attachPreviewLayer(
        _ layer: AVCaptureVideoPreviewLayer,
        position: CaptureAsset.Position
    ) async {
        let layerReference = PreviewLayerReference(value: layer)
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                if let existing = self.previewConnections[position] {
                    self.session.removeConnection(existing)
                }
                self.previewLayers[position] = layerReference.value
                self.previewConnections[position] = nil

                if self.isConfigured {
                    self.session.beginConfiguration()
                    self.connectPreviewLayer(layerReference.value, position: position)
                    self.session.commitConfiguration()
                }
                continuation.resume()
            }
        }
    }

    func detachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) async {
        let layerReference = PreviewLayerReference(value: layer)
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                guard let position = self.previewLayers.first(where: { $0.value === layerReference.value })?.key else {
                    continuation.resume()
                    return
                }

                if let connection = self.previewConnections.removeValue(forKey: position) {
                    self.session.beginConfiguration()
                    self.session.removeConnection(connection)
                    self.session.commitConfiguration()
                }
                self.previewLayers[position] = nil
                layerReference.value.session = nil
                continuation.resume()
            }
        }
    }
}

private extension MultiCamCaptureEngine {
    private func reserveCapture() async throws -> CaptureReservation {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                guard self.session.isRunning else {
                    continuation.resume(throwing: CameraCaptureError.sessionNotReady)
                    return
                }
                guard self.activeCaptureID == nil else {
                    continuation.resume(throwing: CameraCaptureError.captureInProgress)
                    return
                }

                let reservation = CaptureReservation(
                    id: UUID(),
                    rearGeneration: self.rearCollector.currentGeneration(),
                    frontGeneration: self.frontCollector.currentGeneration()
                )
                self.activeCaptureID = reservation.id
                continuation.resume(returning: reservation)
            }
        }
    }

    func validateCapture(
        _ id: UUID,
        emitting phase: CameraCapturePhase? = nil
    ) async throws {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            sessionQueue.async { [weak self] in
                guard let self,
                      self.activeCaptureID == id,
                      self.wantsToRun,
                      self.session.isRunning else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                if let phase {
                    self.emit(.capturePhase(phase))
                }
                continuation.resume()
            }
        }
        try Task.checkCancellation()
    }

    /// Must be called on `sessionQueue` so the active reservation and session lifecycle move together.
    func cancelPendingCapture() {
        activeCaptureID = nil
        rearCollector.cancelAll()
        frontCollector.cancelAll()
    }

    func configureSession() throws {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            throw CameraCaptureError.multiCamUnsupported
        }
        guard let devices = discoverDevicePair() else {
            throw CameraCaptureError.supportedPairUnavailable
        }

        resetSessionConfiguration()
        try configure(device: devices.rear, maximumWidth: 1_920)
        try configure(device: devices.front, maximumWidth: 1_920)

        let rearInput = try AVCaptureDeviceInput(device: devices.rear)
        let frontInput = try AVCaptureDeviceInput(device: devices.front)

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard session.canAddInput(rearInput), session.canAddInput(frontInput) else {
            throw CameraCaptureError.underlying("The selected camera inputs cannot be added to the MultiCam session.")
        }
        session.addInputWithNoConnections(rearInput)
        session.addInputWithNoConnections(frontInput)
        rearInput.videoMinFrameDurationOverride = CMTime(value: 1, timescale: 30)
        frontInput.videoMinFrameDurationOverride = CMTime(value: 1, timescale: 30)

        guard let rearPort = rearInput.ports.first(where: { $0.mediaType == .video }),
              let frontPort = frontInput.ports.first(where: { $0.mediaType == .video }) else {
            throw CameraCaptureError.supportedPairUnavailable
        }

        let rearOutput = makeVideoOutput(collector: rearCollector, queue: rearOutputQueue)
        let frontOutput = makeVideoOutput(collector: frontCollector, queue: frontOutputQueue)
        guard session.canAddOutput(rearOutput) else {
            throw CameraCaptureError.underlying("The device cannot add the rear camera frame output.")
        }
        session.addOutputWithNoConnections(rearOutput)
        guard session.canAddOutput(frontOutput) else {
            throw CameraCaptureError.underlying("The device cannot add the front camera frame output.")
        }
        session.addOutputWithNoConnections(frontOutput)

        let rearConnection = AVCaptureConnection(inputPorts: [rearPort], output: rearOutput)
        let frontConnection = AVCaptureConnection(inputPorts: [frontPort], output: frontOutput)
        configureVideoConnection(rearConnection, position: .rear)
        configureVideoConnection(frontConnection, position: .front)

        guard session.canAddConnection(rearConnection) else {
            throw CameraCaptureError.underlying("The device cannot connect the rear camera frame stream.")
        }
        session.addConnection(rearConnection)
        guard session.canAddConnection(frontConnection) else {
            throw CameraCaptureError.underlying("The device cannot connect the front camera frame stream.")
        }
        session.addConnection(frontConnection)

        self.rearInput = rearInput
        self.frontInput = frontInput
        self.rearPort = rearPort
        self.frontPort = frontPort
        self.rearOutput = rearOutput
        self.frontOutput = frontOutput

        previewLayers.forEach { position, layer in
            connectPreviewLayer(layer, position: position)
        }

        if session.hardwareCost > 1 {
            rearInput.videoMinFrameDurationOverride = CMTime(value: 1, timescale: 20)
            frontInput.videoMinFrameDurationOverride = CMTime(value: 1, timescale: 20)
        }

        guard session.hardwareCost <= 1 else {
            throw CameraCaptureError.underlying(
                "The selected front and rear camera formats exceed this device's MultiCam hardware budget."
            )
        }

        observePressure(on: devices.rear)
        observePressure(on: devices.front)
        isConfigured = true
    }

    func resetSessionConfiguration() {
        turnTorchOffIfNeeded()
        pressureObservations.forEach { $0.invalidate() }
        pressureObservations.removeAll()
        previewConnections.removeAll()
        session.connections.forEach(session.removeConnection)
        session.outputs.forEach(session.removeOutput)
        session.inputs.forEach(session.removeInput)
        rearInput = nil
        frontInput = nil
        rearPort = nil
        frontPort = nil
        rearOutput = nil
        frontOutput = nil
        isConfigured = false
    }

    func discoverDevicePair() -> DevicePair? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .builtInUltraWideCamera,
                .builtInTelephotoCamera,
                .builtInTrueDepthCamera
            ],
            mediaType: .video,
            position: .unspecified
        )

        let pairs = discovery.supportedMultiCamDeviceSets.compactMap { devices -> DevicePair? in
            guard let rear = devices
                .filter({ $0.position == .back })
                .sorted(by: { devicePriority($0) > devicePriority($1) })
                .first,
                  let front = devices
                .filter({ $0.position == .front })
                .sorted(by: { devicePriority($0) > devicePriority($1) })
                .first else {
                return nil
            }
            return DevicePair(rear: rear, front: front)
        }

        return pairs.max { lhs, rhs in
            pairPriority(lhs) < pairPriority(rhs)
        }
    }

    func devicePriority(_ device: AVCaptureDevice) -> Int {
        switch device.deviceType {
        case .builtInWideAngleCamera: 400
        case .builtInTrueDepthCamera: 300
        case .builtInUltraWideCamera: 200
        case .builtInTelephotoCamera: 100
        default: 0
        }
    }

    func pairPriority(_ pair: DevicePair) -> Int {
        devicePriority(pair.rear) + devicePriority(pair.front)
    }

    func configure(device: AVCaptureDevice, maximumWidth: Int32) throws {
        let multiCamFormats = device.formats.filter(\.isMultiCamSupported)
        guard !multiCamFormats.isEmpty else {
            throw CameraCaptureError.supportedPairUnavailable
        }

        let preferredFormats = multiCamFormats.filter {
            let dimensions = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            return dimensions.width <= maximumWidth &&
                $0.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= 30 })
        }
        let candidates = preferredFormats.isEmpty ? multiCamFormats : preferredFormats
        guard let format = candidates.max(by: { formatScore($0) < formatScore($1) }) else {
            throw CameraCaptureError.supportedPairUnavailable
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.activeFormat = format

        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        if device.isSmoothAutoFocusSupported {
            device.isSmoothAutoFocusEnabled = true
        }
        device.isSubjectAreaChangeMonitoringEnabled = true
    }

    func formatScore(_ format: AVCaptureDevice.Format) -> Int64 {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let pixelCount = Int64(dimensions.width) * Int64(dimensions.height)
        let binnedBonus: Int64 = format.isVideoBinned ? 10_000_000 : 0
        let thirtyFPSBonus: Int64 = format.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= 30 })
            ? 5_000_000
            : 0
        return pixelCount + binnedBonus + thirtyFPSBonus
    }

    func makeVideoOutput(
        collector: VideoFrameCollector,
        queue: DispatchQueue
    ) -> AVCaptureVideoDataOutput {
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        output.setSampleBufferDelegate(collector, queue: queue)
        return output
    }

    func connectPreviewLayer(
        _ layer: AVCaptureVideoPreviewLayer,
        position: CaptureAsset.Position
    ) {
        let port = position == .rear ? rearPort : frontPort
        guard let port else { return }

        // MultiCam preview connections are formed manually, so the layer must first
        // be attached to the session without creating an implicit input connection.
        layer.setSessionWithNoConnection(session)
        let connection = AVCaptureConnection(inputPort: port, videoPreviewLayer: layer)
        configureVideoConnection(connection, position: position)
        guard session.canAddConnection(connection) else { return }
        session.addConnection(connection)
        previewConnections[position] = connection
    }

    func configureVideoConnection(
        _ connection: AVCaptureConnection,
        position: CaptureAsset.Position
    ) {
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        if position == .front, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }

    func canUseTorch(on device: AVCaptureDevice) -> Bool {
        device.hasTorch &&
            device.isTorchAvailable &&
            device.isTorchModeSupported(.on) &&
            device.isTorchModeSupported(.off)
    }

    func turnTorchOffIfNeeded() {
        guard let device = rearInput?.device,
              device.hasTorch,
              device.torchMode != .off,
              device.isTorchModeSupported(.off) else { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.torchMode = .off
        } catch {
            // Session shutdown and interruption recovery must continue even if the
            // system has already made the torch unavailable.
        }
    }
}

private extension MultiCamCaptureEngine {
    func installObserversIfNeeded() {
        guard notificationTokens.isEmpty else { return }
        let center = NotificationCenter.default

        notificationTokens = [
            center.addObserver(
                forName: AVCaptureSession.wasInterruptedNotification,
                object: session,
                queue: nil
            ) { [weak self] notification in
                let reasonRawValue = (notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue
                guard let engine = self else { return }
                engine.sessionQueue.async { [engine, reasonRawValue] in
                    engine.handleInterruption(reasonRawValue: reasonRawValue)
                }
            },
            center.addObserver(
                forName: AVCaptureSession.interruptionEndedNotification,
                object: session,
                queue: nil
            ) { [weak self] _ in
                guard let engine = self else { return }
                engine.sessionQueue.async { [engine] in
                    engine.handleInterruptionEnded()
                }
            },
            center.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification,
                object: session,
                queue: nil
            ) { [weak self] notification in
                let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
                let message = error?.localizedDescription ?? "The camera session encountered a runtime error."
                let isMediaServicesReset = error?.code == .mediaServicesWereReset
                guard let engine = self else { return }
                engine.sessionQueue.async { [engine, message, isMediaServicesReset] in
                    engine.handleRuntimeError(
                        message: message,
                        isMediaServicesReset: isMediaServicesReset
                    )
                }
            },
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                guard let engine = self else { return }
                engine.sessionQueue.async { [engine] in
                    engine.turnTorchOffIfNeeded()
                    engine.cancelPendingCapture()
                    if engine.session.isRunning {
                        engine.session.stopRunning()
                    }
                    engine.emit(.stopped)
                }
            },
            center.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                guard let engine = self else { return }
                engine.sessionQueue.async { [engine] in
                    guard engine.wantsToRun, !engine.session.isRunning else { return }
                    engine.session.startRunning()
                    engine.emit(engine.session.isRunning ? .running : .runtimeError(
                        message: "The cameras did not resume after returning to the foreground.",
                        recovered: false
                    ))
                }
            }
        ]
    }

    func handleInterruption(reasonRawValue: Int?) {
        let reason = reasonRawValue.flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
        let message: String

        switch reason {
        case .videoDeviceNotAvailableInBackground:
            message = "Camera capture is paused while the app is in the background."
        case .audioDeviceInUseByAnotherClient, .videoDeviceInUseByAnotherClient:
            message = "Another app is temporarily using the camera."
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            message = "Camera capture is unavailable while multiple apps are active."
        case .videoDeviceNotAvailableDueToSystemPressure:
            message = "The cameras paused because the device is under heavy system pressure."
        case .none:
            message = "The camera session was interrupted."
        default:
            message = "The camera session was interrupted."
        }

        turnTorchOffIfNeeded()
        cancelPendingCapture()
        emit(.interrupted(message: message))
    }

    func handleInterruptionEnded() {
        emit(.interruptionEnded)
        guard wantsToRun else { return }
        if !session.isRunning {
            session.startRunning()
        }
        if session.isRunning {
            emit(.running)
        }
    }

    func handleRuntimeError(message: String, isMediaServicesReset: Bool) {
        var recovered = false

        turnTorchOffIfNeeded()
        cancelPendingCapture()
        if isMediaServicesReset, wantsToRun {
            session.startRunning()
            recovered = session.isRunning
        }

        emit(.runtimeError(
            message: message,
            recovered: recovered
        ))
        if recovered {
            emit(.running)
        }
    }

    func observePressure(on device: AVCaptureDevice) {
        let observation = device.observe(\.systemPressureState, options: [.initial, .new]) { [weak self] device, _ in
            let level = device.systemPressureState.level
            guard let engine = self else { return }
            engine.sessionQueue.async { [engine, level] in
                engine.handlePressure(level)
            }
        }
        pressureObservations.append(observation)
    }

    func handlePressure(_ level: AVCaptureDevice.SystemPressureState.Level) {
        let mappedLevel: CameraPressureLevel
        let maximumFPS: Int32

        switch level {
        case .nominal:
            mappedLevel = .nominal
            maximumFPS = 30
        case .fair:
            mappedLevel = .fair
            maximumFPS = 30
        case .serious:
            mappedLevel = .serious
            maximumFPS = 20
        case .critical:
            mappedLevel = .critical
            maximumFPS = 15
        case .shutdown:
            mappedLevel = .shutdown
            maximumFPS = 15
        default:
            mappedLevel = .critical
            maximumFPS = 15
        }

        if let rearInput, let frontInput {
            session.beginConfiguration()
            rearInput.videoMinFrameDurationOverride = CMTime(value: 1, timescale: maximumFPS)
            frontInput.videoMinFrameDurationOverride = CMTime(value: 1, timescale: maximumFPS)
            session.commitConfiguration()
        }
        if mappedLevel == .shutdown {
            turnTorchOffIfNeeded()
            cancelPendingCapture()
        }
        emit(.pressureChanged(mappedLevel))
    }

    func emit(_ event: CameraSessionEvent) {
        let continuations = eventLock.synchronized {
            Array(eventContinuations.values)
        }
        continuations.forEach { $0.yield(event) }
    }
}
