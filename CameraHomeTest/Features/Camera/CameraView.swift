import SwiftUI
import UIKit

struct CameraView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: CameraViewModel
    @State private var frontIsPrimary = false
    @State private var torchErrorMessage: String?
    private let previewSource: any CameraPreviewSource

    init(
        cameraClient: any CameraCaptureClient,
        previewSource: any CameraPreviewSource,
        repository: any CaptureRepository
    ) {
        _viewModel = State(
            initialValue: CameraViewModel(
                cameraClient: cameraClient,
                repository: repository
            )
        )
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
        .alert(
            "Unable to Control Torch",
            isPresented: Binding(
                get: { torchErrorMessage != nil },
                set: { if !$0 { torchErrorMessage = nil } }
            )
        ) {
            Button("OK") { torchErrorMessage = nil }
        } message: {
            Text(torchErrorMessage ?? CameraCaptureError.torchUnavailable.localizedDescription)
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
            CameraPreviewPane(previewSource: previewSource, position: .rear)
                .previewPlacement(
                    position: .rear,
                    isInset: frontIsPrimary,
                    isEmphasized: false
                )
                .zIndex(frontIsPrimary ? 2 : 0)

            CameraPreviewPane(previewSource: previewSource, position: .front)
                .previewPlacement(
                    position: .front,
                    isInset: !frontIsPrimary,
                    isEmphasized: !frontIsPrimary && viewModel.frontCaptureProgress != nil
                )
                .zIndex(frontIsPrimary ? 0 : 2)

            VStack {
                Spacer()

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(frontIsPrimary ? "FRONT" : "REAR", systemImage: "camera.fill")
                            .font(.caption2.weight(.heavy))
                            .tracking(1.4)
                            .foregroundStyle(AppTheme.accent)

                        Text(
                            frontIsPrimary
                                ? "Captures 1.5 seconds after rear"
                                : "First frame captures instantly"
                        )
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
            .zIndex(3)

            if viewModel.showsSupportCard {
                supportCard
                    .padding(14)
                    .padding(.top, 166)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(4)
            }

            if let progress = viewModel.frontCaptureProgress {
                CaptureSequenceHUD(progress: progress)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(5)
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
        .animation(stageAnimation, value: viewModel.showsSupportCard)
        .animation(stageAnimation, value: viewModel.frontCaptureProgress != nil)
        .animation(stageAnimation, value: frontIsPrimary)
    }

    var supportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            if viewModel.canRetry {
                Button {
                    Task { await viewModel.retry() }
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.accent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 18)
    }

    var captureControls: some View {
        HStack {
            ControlButton(
                systemImage: viewModel.isTorchEnabled ? "bolt.fill" : "bolt.slash.fill",
                label: "Torch",
                isSelected: viewModel.isTorchEnabled,
                isEnabled: viewModel.isTorchAvailable &&
                    !viewModel.isTorchChanging &&
                    viewModel.state == .ready,
                accessibilityValue: viewModel.isTorchEnabled ? "On" : "Off"
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task {
                    do {
                        try await viewModel.toggleTorch()
                    } catch {
                        torchErrorMessage = error.localizedDescription
                    }
                }
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                Task {
                    guard let capture = await viewModel.capture() else { return }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    coordinator.presentSavedCapture(id: capture.id)
                }
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
            .scaleEffect(viewModel.isCaptureEnabled ? 1 : 0.92)
            .animation(stageAnimation, value: viewModel.isCaptureEnabled)
            .accessibilityLabel("Capture rear and front photos")

            Spacer()

            ControlButton(
                systemImage: "arrow.triangle.2.circlepath.camera.fill",
                label: "Swap",
                isSelected: frontIsPrimary,
                isEnabled: true,
                accessibilityValue: frontIsPrimary ? "Front camera primary" : "Rear camera primary"
            ) {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(stageAnimation) {
                    frontIsPrimary.toggle()
                }
            }
        }
        .padding(.horizontal, 10)
    }

    var stageAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.84)
    }
}

private struct CameraPreviewPane: View {
    let previewSource: any CameraPreviewSource
    let position: CaptureAsset.Position

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(glowColor)
                .frame(width: position == .rear ? 320 : 150)
                .blur(radius: position == .rear ? 42 : 24)
                .offset(
                    x: position == .rear ? -120 : 50,
                    y: position == .rear ? -190 : -80
                )

            Image(systemName: position == .rear ? "mountain.2.fill" : "person.crop.circle.fill")
                .font(.system(size: position == .rear ? 100 : 72, weight: .light))
                .foregroundStyle(.white.opacity(position == .rear ? 0.12 : 0.72))

            CameraPreviewLayerView(source: previewSource, position: position)

            if position == .rear {
                ViewfinderGrid()
                    .stroke(.white.opacity(0.08), lineWidth: 0.8)
            }
        }
        .accessibilityLabel(position == .rear ? "Rear camera preview" : "Front camera preview")
    }

    private var colors: [Color] {
        switch position {
        case .rear:
            [Color(red: 0.16, green: 0.19, blue: 0.25), Color(red: 0.05, green: 0.07, blue: 0.11)]
        case .front:
            [AppTheme.coral.opacity(0.95), Color(red: 0.26, green: 0.09, blue: 0.16)]
        }
    }

    private var glowColor: Color {
        position == .rear ? AppTheme.accent.opacity(0.15) : .white.opacity(0.14)
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
    let isSelected: Bool
    let isEnabled: Bool
    let accessibilityValue: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(isSelected ? .black : .white)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? AppTheme.accent : AppTheme.surface, in: Circle())
                    .overlay {
                        Circle().stroke(
                            isSelected ? AppTheme.accent.opacity(0.8) : AppTheme.subtleBorder
                        )
                    }

                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isSelected ? AppTheme.accent : .secondary)
            }
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.42)
        .disabled(!isEnabled)
        .accessibilityValue(accessibilityValue)
    }
}

private extension View {
    func previewPlacement(
        position: CaptureAsset.Position,
        isInset: Bool,
        isEmphasized: Bool
    ) -> some View {
        frame(
            maxWidth: isInset ? nil : .infinity,
            maxHeight: isInset ? nil : .infinity
        )
        .frame(
            width: isInset ? 118 : nil,
            height: isInset ? 158 : nil
        )
        .clipShape(
            RoundedRectangle(cornerRadius: isInset ? 22 : 0, style: .continuous)
        )
        .overlay {
            if isInset {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.3), lineWidth: 1.5)
            }
        }
        .overlay(alignment: .bottom) {
            if isInset {
                Text(position == .rear ? "REAR · FIRST" : "FRONT · +1.5s")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.8)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.3), in: Capsule())
                    .padding(9)
            }
        }
        .shadow(color: .black.opacity(isInset ? 0.4 : 0), radius: 16, y: 8)
        .padding(isInset ? 14 : 0)
        .scaleEffect(isEmphasized ? 1.035 : 1)
    }
}

private struct CaptureSequenceHUD: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    .animation(reduceMotion ? nil : .linear(duration: 0.06), value: progress)

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
    CameraView(
        cameraClient: camera,
        previewSource: camera,
        repository: InMemoryCaptureRepository()
    )
        .environment(AppCoordinator())
        .preferredColorScheme(.dark)
}
