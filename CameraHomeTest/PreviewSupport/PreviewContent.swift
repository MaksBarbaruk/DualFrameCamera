import Foundation

extension AppContainer {
    static func preview() -> AppContainer {
        let camera = UnavailableCameraCaptureClient()
        return AppContainer(
            captureRepository: InMemoryCaptureRepository(captures: CapturePair.previewSamples),
            cameraCaptureClient: camera,
            cameraPreviewSource: camera
        )
    }
}

extension CapturePair {
    static let previewSamples: [CapturePair] = (0..<6).map { index in
        let createdAt = Date().addingTimeInterval(TimeInterval(-index * 3_700))
        return CapturePair(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
            createdAt: createdAt,
            rear: CaptureAsset(
                position: .rear,
                fileURL: URL(fileURLWithPath: "/preview/rear-\(index).heic"),
                pixelWidth: 1_920,
                pixelHeight: 1_080,
                capturedAt: createdAt,
                captureUptimeNanoseconds: UInt64(index) * 1_000_000_000
            ),
            front: CaptureAsset(
                position: .front,
                fileURL: URL(fileURLWithPath: "/preview/front-\(index).heic"),
                pixelWidth: 1_920,
                pixelHeight: 1_080,
                capturedAt: createdAt.addingTimeInterval(1.5),
                captureUptimeNanoseconds: UInt64(index) * 1_000_000_000 + 1_500_000_000
            )
        )
    }
}
