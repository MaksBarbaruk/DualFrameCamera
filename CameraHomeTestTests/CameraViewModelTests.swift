import Foundation
import Testing
@testable import CameraHomeTest

@MainActor
struct CameraViewModelTests {
    @Test
    func successfulCapturePersistsPairAndReturnsPublishedModel() async throws {
        let camera = SuspendedCameraClient()
        let repository = RecordingCaptureRepository()
        let viewModel = CameraViewModel(
            cameraClient: camera,
            repository: repository
        )
        await viewModel.prepare()

        let captureTask = Task { await viewModel.capture() }
        try await waitForCaptureRequest(on: camera)
        let payload = makePayload()
        await camera.completeCapture(with: payload)

        let capture = try #require(await captureTask.value)
        #expect(capture.id == payload.id)
        #expect(viewModel.state == .ready)
        #expect(await repository.savedPayloadIDs() == [payload.id])
    }

    @Test
    func secondShutterRequestIsRejectedWhilePairIsInFlight() async throws {
        let camera = SuspendedCameraClient()
        let repository = RecordingCaptureRepository()
        let viewModel = CameraViewModel(
            cameraClient: camera,
            repository: repository
        )
        await viewModel.prepare()

        let firstCapture = Task { await viewModel.capture() }
        try await waitForCaptureRequest(on: camera)
        let secondCapture = await viewModel.capture()

        #expect(secondCapture == nil)
        #expect(await camera.captureRequestCount() == 1)

        await camera.completeCapture(with: makePayload())
        _ = await firstCapture.value
    }

    @Test
    func captureFailureProducesVisibleRecoverableState() async throws {
        let camera = SuspendedCameraClient()
        let repository = RecordingCaptureRepository()
        let viewModel = CameraViewModel(
            cameraClient: camera,
            repository: repository
        )
        await viewModel.prepare()

        let captureTask = Task { await viewModel.capture() }
        try await waitForCaptureRequest(on: camera)
        await camera.failCapture()
        let capture = await captureTask.value

        #expect(capture == nil)
        #expect(viewModel.showsSupportCard)
        #expect(viewModel.canRetry)
        #expect(viewModel.supportTitle == "Capture failed")
    }

    @Test
    func lifecycleCancellationDoesNotPublishOrPresentAnError() async throws {
        let camera = SuspendedCameraClient()
        let repository = RecordingCaptureRepository()
        let viewModel = CameraViewModel(
            cameraClient: camera,
            repository: repository
        )
        await viewModel.prepare()

        let captureTask = Task { await viewModel.capture() }
        try await waitForCaptureRequest(on: camera)
        await camera.cancelCapture()
        let capture = await captureTask.value

        #expect(capture == nil)
        #expect(viewModel.state == .idle)
        #expect(!viewModel.showsSupportCard)
        #expect(await repository.savedPayloadIDs().isEmpty)
    }
}

private extension CameraViewModelTests {
    enum TestFailure: Error {
        case captureDidNotStart
    }

    func waitForCaptureRequest(on camera: SuspendedCameraClient) async throws {
        for _ in 0..<100 {
            if await camera.captureRequestCount() == 1 { return }
            await Task.yield()
        }
        throw TestFailure.captureDidNotStart
    }

    func makePayload() -> CapturedPairPayload {
        let rearDate = Date(timeIntervalSince1970: 1_700_000_000)
        return CapturedPairPayload(
            id: UUID(),
            createdAt: rearDate,
            rear: CapturedImagePayload(
                data: Data("rear".utf8),
                pixelWidth: 1_920,
                pixelHeight: 1_080,
                capturedAt: rearDate,
                captureUptimeNanoseconds: 1_000_000_000
            ),
            front: CapturedImagePayload(
                data: Data("front".utf8),
                pixelWidth: 1_920,
                pixelHeight: 1_080,
                capturedAt: rearDate.addingTimeInterval(1.5),
                captureUptimeNanoseconds: 2_500_000_000
            )
        )
    }
}

private actor SuspendedCameraClient: CameraCaptureClient {
    private var captureContinuation: CheckedContinuation<CapturedPairPayload, any Error>?
    private var requestCount = 0

    func authorizationStatus() -> CameraAuthorization { .authorized }
    func requestAuthorization() -> CameraAuthorization { .authorized }
    func capability() -> CameraCapability { .available }
    func start() { }
    func stop() { }

    func capturePair() async throws -> CapturedPairPayload {
        requestCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            captureContinuation = continuation
        }
    }

    func sessionEvents() -> AsyncStream<CameraSessionEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func captureRequestCount() -> Int {
        requestCount
    }

    func completeCapture(with payload: CapturedPairPayload) {
        captureContinuation?.resume(returning: payload)
        captureContinuation = nil
    }

    func failCapture() {
        captureContinuation?.resume(
            throwing: CameraCaptureError.underlying("Synthetic failure")
        )
        captureContinuation = nil
    }

    func cancelCapture() {
        captureContinuation?.resume(throwing: CancellationError())
        captureContinuation = nil
    }
}

private actor RecordingCaptureRepository: CaptureRepository {
    private var payloadIDs: [UUID] = []

    func captures() -> [CapturePair] { [] }
    func capture(id: UUID) -> CapturePair? { nil }

    func save(_ payload: CapturedPairPayload) -> CapturePair {
        payloadIDs.append(payload.id)
        let directory = URL(fileURLWithPath: "/recording/\(payload.id.uuidString)")
        return CapturePair(
            id: payload.id,
            createdAt: payload.createdAt,
            rear: asset(from: payload.rear, position: .rear, directory: directory),
            front: asset(from: payload.front, position: .front, directory: directory)
        )
    }

    func delete(id: UUID) { }

    func savedPayloadIDs() -> [UUID] {
        payloadIDs
    }

    private func asset(
        from payload: CapturedImagePayload,
        position: CaptureAsset.Position,
        directory: URL
    ) -> CaptureAsset {
        CaptureAsset(
            position: position,
            fileURL: directory.appendingPathComponent("\(position.rawValue).heic"),
            pixelWidth: payload.pixelWidth,
            pixelHeight: payload.pixelHeight,
            capturedAt: payload.capturedAt,
            captureUptimeNanoseconds: payload.captureUptimeNanoseconds
        )
    }
}
