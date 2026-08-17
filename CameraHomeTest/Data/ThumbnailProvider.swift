import Foundation
import ImageIO
@preconcurrency import UIKit

nonisolated final class ThumbnailProvider: @unchecked Sendable {
    private struct SendableImage: @unchecked Sendable {
        let value: UIImage
    }

    static let shared = ThumbnailProvider()

    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 80
        cache.totalCostLimit = 80 * 1_024 * 1_024
    }

    func image(at url: URL, maxPixelSize: Int) async -> UIImage? {
        let boundedSize = min(max(maxPixelSize, 240), 2_048)
        let cacheKey = "\(url.path)#\(boundedSize)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let loaded = await Task.detached(priority: .utility) {
            let sourceOptions = [
                kCGImageSourceShouldCache: false
            ] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
                return nil as SendableImage?
            }

            let thumbnailOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: boundedSize
            ] as CFDictionary
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                thumbnailOptions
            ) else {
                return nil as SendableImage?
            }

            return SendableImage(value: UIImage(cgImage: cgImage))
        }.value

        guard let loaded else { return nil }
        let cost = Int(loaded.value.size.width * loaded.value.size.height * 4)
        cache.setObject(loaded.value, forKey: cacheKey, cost: cost)
        return loaded.value
    }
}
