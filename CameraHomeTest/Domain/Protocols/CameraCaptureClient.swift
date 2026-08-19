import Foundation

nonisolated struct CapturedImagePayload: Sendable {
    let data: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let capturedAt: Date
    let captureUptimeNanoseconds: UInt64
}

nonisolated struct CapturedPairPayload: Sendable {
    let id: UUID
    let createdAt: Date
    let rear: CapturedImagePayload
    let front: CapturedImagePayload
}

nonisolated protocol CameraCaptureClient: Sendable {
    func authorizationStatus() async -> CameraAuthorization
    func requestAuthorization() async -> CameraAuthorization
    func capability() async -> CameraCapability
    func start() async throws
    func stop() async
    func isTorchAvailable() async -> Bool
    func setTorchEnabled(_ enabled: Bool) async throws
    func capturePair() async throws -> CapturedPairPayload
    func sessionEvents() async -> AsyncStream<CameraSessionEvent>
}
