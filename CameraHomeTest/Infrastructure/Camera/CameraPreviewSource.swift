@preconcurrency import AVFoundation
import Foundation

nonisolated protocol CameraPreviewSource: AnyObject, Sendable {
    func attachPreviewLayer(
        _ layer: AVCaptureVideoPreviewLayer,
        position: CaptureAsset.Position
    ) async

    func detachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) async
}
