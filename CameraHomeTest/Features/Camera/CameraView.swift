import SwiftUI

struct CameraView: View {
    @State private var viewModel: CameraViewModel
    private let previewSource: any CameraPreviewSource

    init(
        cameraClient: any CameraCaptureClient,
        previewSource: any CameraPreviewSource
    ) {
        _viewModel = State(initialValue: CameraViewModel(cameraClient: cameraClient))
        self.previewSource = previewSource
    }

    var body: some View {
        ZStack {
            AppBackground()

            GeometryReader { geometry in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        header
                        cameraStage(height: min(geometry.size.height * 0.64, 610))
                        captureControls
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.prepare()
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}

private extension CameraView {
    var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("DUAL FRAME")
                    .font(.caption.weight(.heavy))
                    .tracking(2.2)
                    .foregroundStyle(AppTheme.accent)

                Text("Capture both sides")
                    .font(.title2.bold())
            }

            Spacer()

            StatusPill(
                title: viewModel.statusText,
                systemImage: viewModel.state == .ready ? "circle.fill" : "sparkles",
                tint: viewModel.state == .ready ? .green : AppTheme.accent
            )
        }
    }

    func cameraStage(height: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            RearCameraPlaceholder(previewSource: previewSource)

            FrontCameraPlaceholder(previewSource: previewSource)
                .frame(width: 118, height: 158)
                .padding(14)

            VStack {
                Spacer()

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("REAR", systemImage: "camera.fill")
                            .font(.caption2.weight(.heavy))
                            .tracking(1.4)
                            .foregroundStyle(AppTheme.accent)

                        Text("First frame captures instantly")
                            .font(.subheadline.weight(.semibold))
                    }

                    Spacer()

                    Image(systemName: "viewfinder")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(18)
                .background(.ultraThinMaterial)
            }

            if viewModel.showsSupportCard {
                supportCard
                    .padding(14)
                    .padding(.top, 166)
            }

            if let progress = viewModel.frontCaptureProgress {
                CaptureSequenceHUD(progress: progress)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(AppTheme.subtleBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.42), radius: 28, y: 16)
    }

    var supportCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 34, height: 34)
                .background(AppTheme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 5) {
                Text(viewModel.supportTitle)
                    .font(.subheadline.bold())

                Text(viewModel.supportMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 18)
    }

    var captureControls: some View {
        HStack {
            ControlButton(systemImage: "bolt.slash.fill", label: "Flash")

            Spacer()

            Button {
                Task { await viewModel.capture() }
            } label: {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(viewModel.isCaptureEnabled ? 1 : 0.38), lineWidth: 4)
                        .frame(width: 82, height: 82)

                    Circle()
                        .fill(viewModel.isCaptureEnabled ? .white : .white.opacity(0.3))
                        .frame(width: 64, height: 64)

                    Circle()
                        .fill(AppTheme.coral)
                        .frame(width: 18, height: 18)
                }
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isCaptureEnabled)
            .accessibilityLabel("Capture rear and front photos")

            Spacer()

            ControlButton(systemImage: "arrow.triangle.2.circlepath.camera.fill", label: "Swap")
        }
        .padding(.horizontal, 10)
    }
}

private struct RearCameraPlaceholder: View {
    let previewSource: any CameraPreviewSource

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.19, blue: 0.25),
                    Color(red: 0.05, green: 0.07, blue: 0.11)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(AppTheme.accent.opacity(0.15))
                .frame(width: 320)
                .blur(radius: 42)
                .offset(x: -120, y: -190)

            Image(systemName: "mountain.2.fill")
                .font(.system(size: 100, weight: .light))
                .foregroundStyle(.white.opacity(0.12))

            CameraPreviewLayerView(source: previewSource, position: .rear)

            ViewfinderGrid()
                .stroke(.white.opacity(0.08), lineWidth: 0.8)
        }
    }
}

private struct FrontCameraPlaceholder: View {
    let previewSource: any CameraPreviewSource

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.coral.opacity(0.95), Color(red: 0.26, green: 0.09, blue: 0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.white.opacity(0.14))
                .frame(width: 96)
                .offset(x: 40, y: -60)

            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 62))
                .foregroundStyle(.white.opacity(0.82))

            CameraPreviewLayerView(source: previewSource, position: .front)

            VStack {
                Spacer()
                Text("FRONT · +1.5s")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.8)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.3), in: Capsule())
                    .padding(9)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.3), lineWidth: 1.5)
        }
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
    }
}

private struct ViewfinderGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width / 3, y: 0))
        path.addLine(to: CGPoint(x: rect.width / 3, y: rect.height))
        path.move(to: CGPoint(x: rect.width * 2 / 3, y: 0))
        path.addLine(to: CGPoint(x: rect.width * 2 / 3, y: rect.height))
        path.move(to: CGPoint(x: 0, y: rect.height / 3))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height / 3))
        path.move(to: CGPoint(x: 0, y: rect.height * 2 / 3))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height * 2 / 3))
        return path
    }
}

private struct ControlButton: View {
    let systemImage: String
    let label: String

    var body: some View {
        Button(action: {}) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.surface, in: Circle())
                    .overlay { Circle().stroke(AppTheme.subtleBorder) }

                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(true)
    }
}

private struct CaptureSequenceHUD: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 7)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AppTheme.accent,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Image(systemName: "person.crop.circle")
                    .font(.title)
                    .foregroundStyle(.white)
            }
            .frame(width: 72, height: 72)

            VStack(spacing: 3) {
                Text("Hold steady")
                    .font(.headline)
                Text("Front camera is next")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .glassCard(cornerRadius: 24)
    }
}

#Preview {
    let camera = UnavailableCameraCaptureClient()
    CameraView(cameraClient: camera, previewSource: camera)
        .preferredColorScheme(.dark)
}
