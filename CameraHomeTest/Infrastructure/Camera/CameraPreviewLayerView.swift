@preconcurrency import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewLayerView: UIViewRepresentable {
    let source: any CameraPreviewSource
    let position: CaptureAsset.Position

    func makeUIView(context: Context) -> PreviewSurfaceView {
        let view = PreviewSurfaceView()
        view.source = source
        view.previewLayer.videoGravity = .resizeAspectFill

        Task {
            await source.attachPreviewLayer(view.previewLayer, position: position)
        }

        return view
    }

    func updateUIView(_ uiView: PreviewSurfaceView, context: Context) { }

    static func dismantleUIView(_ uiView: PreviewSurfaceView, coordinator: Void) {
        guard let source = uiView.source else { return }
        let layer = uiView.previewLayer
        Task {
            await source.detachPreviewLayer(layer)
        }
    }

    final class PreviewSurfaceView: UIView {
        weak var source: (any CameraPreviewSource)?

        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isOpaque = false
            previewLayer.backgroundColor = UIColor.clear.cgColor
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
