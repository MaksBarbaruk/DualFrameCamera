import SwiftUI

struct FeedView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var viewModel: FeedViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 154, maximum: 220), spacing: 14)
    ]

    init(repository: any CaptureRepository) {
        _viewModel = State(initialValue: FeedViewModel(repository: repository))
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    if viewModel.isLoading && viewModel.captures.isEmpty {
                        loadingView
                    } else if let errorMessage = viewModel.errorMessage {
                        errorView(errorMessage)
                    } else if viewModel.captures.isEmpty {
                        emptyView
                    } else {
                        captureGrid
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .refreshable {
                await viewModel.load()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.load()
        }
    }
}

private extension FeedView {
    var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text("MOMENTS")
                    .font(.caption.weight(.heavy))
                    .tracking(2.2)
                    .foregroundStyle(AppTheme.accent)

                Text("Your dual frames")
                    .font(.largeTitle.bold())

                Text(viewModel.captures.isEmpty ? "Rear and front, kept together." : captureCountText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !viewModel.captures.isEmpty {
                StatusPill(
                    title: "\(viewModel.captures.count)",
                    systemImage: "photo.stack.fill"
                )
            }
        }
    }

    var captureCountText: String {
        "\(viewModel.captures.count) paired \(viewModel.captures.count == 1 ? "moment" : "moments")"
    }

    var captureGrid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(viewModel.captures) { capture in
                Button {
                    coordinator.showCapture(id: capture.id)
                } label: {
                    CaptureGridTile(capture: capture)
                }
                .buttonStyle(.plain)
            }
        }
    }

    var emptyView: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.coral.opacity(0.32), AppTheme.accent.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "rectangle.inset.filled.and.person.filled")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(height: 190)

            Text("One moment. Two perspectives.")
                .font(.title3.bold())

            Text("Your rear and front photos stay as separate full-quality assets and appear here as a pair.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 310)

            Button {
                coordinator.select(.camera)
            } label: {
                Label("Open Camera", systemImage: "camera.fill")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22)
                    .frame(height: 50)
                    .background(AppTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 30)
    }

    var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(AppTheme.accent)
            Text("Loading moments")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    func errorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(AppTheme.coral)
            Text("Unable to load moments")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassCard()
    }
}

private struct CaptureGridTile: View {
    let capture: CapturePair

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CaptureArtworkView(capture: capture)
                .frame(height: 212)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(capture.createdAt, format: .dateTime.month(.abbreviated).day())
                        .font(.subheadline.bold())
                    Text(capture.createdAt, format: .dateTime.hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .glassCard(cornerRadius: 22)
    }
}

#Preview("Populated feed") {
    FeedView(repository: InMemoryCaptureRepository(captures: CapturePair.previewSamples))
        .environment(AppCoordinator())
        .preferredColorScheme(.dark)
}

