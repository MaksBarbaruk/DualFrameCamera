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
                CameraView(
                    cameraClient: container.cameraCaptureClient,
                    previewSource: container.cameraPreviewSource
                )
                    .tag(AppTab.camera)
                    .tabItem {
                        Label(AppTab.camera.title, systemImage: AppTab.camera.systemImage)
                    }

                FeedView(repository: container.captureRepository)
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
                case .captureDetail(let id):
                    CaptureDetailView(
                        captureID: id,
                        repository: container.captureRepository
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

#Preview("Camera") {
    AppRootView(container: .preview())
        .environment(AppCoordinator())
        .environment(ProgressController())
        .preferredColorScheme(.dark)
}
