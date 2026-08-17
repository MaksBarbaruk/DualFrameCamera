import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO

nonisolated final class PixelBufferEncoder: @unchecked Sendable {
    private let context = CIContext(options: [
        .cacheIntermediates: false,
        .priorityRequestLow: false
    ])

    func encodeHEIF(_ frame: CapturedVideoFrame) throws -> CapturedImagePayload {
        let image = CIImage(cvPixelBuffer: frame.pixelBuffer)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

        guard let data = context.heifRepresentation(
            of: image,
            format: .RGBA8,
            colorSpace: colorSpace,
            options: [
                CIImageRepresentationOption(
                    rawValue: kCGImageDestinationLossyCompressionQuality as String
                ): 0.94
            ]
        ) else {
            throw CameraCaptureError.underlying("The captured camera frame could not be encoded.")
        }

        return CapturedImagePayload(
            data: data,
            pixelWidth: Int(image.extent.width),
            pixelHeight: Int(image.extent.height),
            capturedAt: frame.capturedAt,
            captureUptimeNanoseconds: frame.uptimeNanoseconds
        )
    }
}
