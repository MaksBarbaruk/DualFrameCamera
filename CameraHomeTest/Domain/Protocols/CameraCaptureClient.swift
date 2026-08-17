import Foundation

struct CapturedImagePayload: Sendable {
    let data: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let capturedAt: Date
    let captureUptimeNanoseconds: UInt64
}

struct CapturedPairPayload: Sendable {
    let id: UUID
    let createdAt: Date
    let rear: CapturedImagePayload
    let front: CapturedImagePayload
}

protocol CameraCaptureClient: Sendable {
    func authorizationStatus() async -> CameraAuthorization
    func requestAuthorization() async -> CameraAuthorization
    func capability() async -> CameraCapability
    func start() async throws
    func stop() async
    func capturePair() async throws -> CapturedPairPayload
}

