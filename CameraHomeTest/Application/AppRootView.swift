import SwiftUI

struct AppRootView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(ProgressController.self) private var progressController

    let container: AppContainer

    var body: some View {
        @Bindable var coordinator = coordinator
        @Bindable var progressController = progressController

        NavigationStack(path: $coordinator.path) {
            TabView(selection: $coordinator.selectedTab) {
                ArchitecturePlaceholderView(
                    title: "Camera foundation ready",
                    message: "The live dual-camera experience is the next milestone.",
                    symbol: "camera.aperture"
                )
                .tag(AppTab.camera)
                .tabItem {
                    Label(AppTab.camera.title, systemImage: AppTab.camera.systemImage)
                }

                ArchitecturePlaceholderView(
                    title: "Your moments",
                    message: "Paired captures will appear here after they are saved.",
                    symbol: "square.grid.2x2"
                )
                .tag(AppTab.feed)
                .tabItem {
                    Label(AppTab.feed.title, systemImage: AppTab.feed.systemImage)
                }
            }
            .tint(AppTheme.accent)
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .captureDetail:
                    ArchitecturePlaceholderView(
                        title: "Capture detail",
                        message: "The full-resolution paired review is coming next.",
                        symbol: "photo.on.rectangle.angled"
                    )
                }
            }
        }
        .alert(item: $progressController.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

private struct ArchitecturePlaceholderView: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 18) {
                Image(systemName: symbol)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 88, height: 88)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28))

                Text(title)
                    .font(.title2.bold())

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            .padding(32)
        }
    }
}

#Preview {
    AppRootView(container: .live())
        .environment(AppCoordinator())
        .environment(ProgressController())
        .preferredColorScheme(.dark)
}

