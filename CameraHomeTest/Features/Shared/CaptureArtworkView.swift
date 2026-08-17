import SwiftUI
import UIKit

struct CaptureArtworkView: View {
    let capture: CapturePair
    var frontIsPrimary = false

    private var primaryAsset: CaptureAsset {
        frontIsPrimary ? capture.front : capture.rear
    }

    private var insetAsset: CaptureAsset {
        frontIsPrimary ? capture.rear : capture.front
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                LocalAssetImage(
                    asset: primaryAsset,
                    fallbackColors: frontIsPrimary ? frontColors : rearColors,
                    symbol: frontIsPrimary ? "person.fill" : "mountain.2.fill"
                )

                LocalAssetImage(
                    asset: insetAsset,
                    fallbackColors: frontIsPrimary ? rearColors : frontColors,
                    symbol: frontIsPrimary ? "mountain.2.fill" : "person.fill"
                )
                .frame(
                    width: max(82, geometry.size.width * 0.31),
                    height: max(110, geometry.size.height * 0.31)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.48), lineWidth: 1.5)
                }
                .shadow(color: .black.opacity(0.4), radius: 12, y: 7)
                .padding(12)

                VStack {
                    Spacer()
                    HStack {
                        Text(frontIsPrimary ? "FRONT" : "REAR")
                            .font(.caption2.weight(.heavy))
                            .tracking(1.3)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.38), in: Capsule())
                        Spacer()
                    }
                    .padding(12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var rearColors: [Color] {
        [Color(red: 0.16, green: 0.22, blue: 0.30), Color(red: 0.04, green: 0.07, blue: 0.12)]
    }

    private var frontColors: [Color] {
        [AppTheme.coral, Color(red: 0.25, green: 0.06, blue: 0.14)]
    }
}

private struct LocalAssetImage: View {
    let asset: CaptureAsset
    let fallbackColors: [Color]
    let symbol: String

    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: fallbackColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }
            .clipped()
            .task(id: requestID(for: geometry.size)) {
                guard asset.fileURL.isFileURL else { return }
                image = await ThumbnailProvider.shared.image(
                    at: asset.fileURL,
                    maxPixelSize: maxPixelSize(for: geometry.size)
                )
            }
        }
    }

    private func requestID(for size: CGSize) -> String {
        "\(asset.fileURL.path)#\(maxPixelSize(for: size))"
    }

    private func maxPixelSize(for size: CGSize) -> Int {
        Int(max(size.width, size.height) * UIScreen.main.scale)
    }
}
