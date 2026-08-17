import SwiftUI

struct CaptureDetailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: CaptureDetailViewModel

    init(captureID: UUID, repository: any CaptureRepository) {
        _viewModel = State(
            initialValue: CaptureDetailViewModel(
                captureID: captureID,
                repository: repository
            )
        )
    }

    var body: some View {
        ZStack {
            AppBackground()

            if let capture = viewModel.capture {
                detail(capture)
            } else if viewModel.isLoading {
                ProgressView("Loading moment")
                    .tint(AppTheme.accent)
            } else {
                ContentUnavailableView(
                    "Moment unavailable",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text(viewModel.errorMessage ?? "This paired capture could not be loaded.")
                )
            }
        }
        .navigationTitle("Moment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .task {
            await viewModel.load()
        }
    }
}

private extension CaptureDetailView {
    func detail(_ capture: CapturePair) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                CaptureArtworkView(
                    capture: capture,
                    frontIsPrimary: viewModel.showsFrontAsPrimary
                )
                .frame(height: 520)

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(capture.createdAt, format: .dateTime.weekday(.wide).month(.wide).day())
                            .font(.headline)
                        Text(capture.createdAt, format: .dateTime.hour().minute().second())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82)) {
                            viewModel.swapPrimaryImage()
                        }
                    } label: {
                        Label("Swap", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 14)
                            .frame(height: 42)
                            .background(AppTheme.surface, in: Capsule())
                            .overlay { Capsule().stroke(AppTheme.subtleBorder) }
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .glassCard(cornerRadius: 20)
            }
            .padding(16)
            .padding(.bottom, 24)
        }
    }
}

#Preview {
    NavigationStack {
        CaptureDetailView(
            captureID: CapturePair.previewSamples[0].id,
            repository: InMemoryCaptureRepository(captures: CapturePair.previewSamples)
        )
    }
    .preferredColorScheme(.dark)
}
