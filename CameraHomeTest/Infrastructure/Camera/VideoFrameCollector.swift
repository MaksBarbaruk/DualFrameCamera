@preconcurrency import AVFoundation
import Foundation

nonisolated struct CapturedVideoFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let capturedAt: Date
    let uptimeNanoseconds: UInt64
}

nonisolated final class VideoFrameCollector: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [UUID: CheckedContinuation<CapturedVideoFrame, Error>] = [:]
    private var cancelledWaiters: Set<UUID> = []

    func captureNextFrame() async throws -> CapturedVideoFrame {
        let requestID = UUID()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.synchronized {
                    if cancelledWaiters.remove(requestID) != nil {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        waiters[requestID] = continuation
                    }
                }
            }
        } onCancel: {
            cancelWaiter(id: requestID)
        }
    }

    func cancelAll() {
        let continuations: [CheckedContinuation<CapturedVideoFrame, any Error>] = lock.synchronized {
            let continuations = Array(waiters.values)
            waiters.removeAll()
            cancelledWaiters.removeAll()
            return continuations
        }

        continuations.forEach { $0.resume(throwing: CancellationError()) }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let frame = CapturedVideoFrame(
            pixelBuffer: pixelBuffer,
            capturedAt: Date(),
            uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
        )

        let continuations: [CheckedContinuation<CapturedVideoFrame, any Error>] = lock.synchronized {
            guard !waiters.isEmpty else { return [] }
            let continuations = Array(waiters.values)
            waiters.removeAll()
            return continuations
        }

        continuations.forEach { $0.resume(returning: frame) }
    }

    private func cancelWaiter(id: UUID) {
        let continuation: CheckedContinuation<CapturedVideoFrame, any Error>? = lock.synchronized {
            if let continuation = waiters.removeValue(forKey: id) {
                return continuation
            }

            cancelledWaiters.insert(id)
            return nil
        }

        continuation?.resume(throwing: CancellationError())
    }
}
