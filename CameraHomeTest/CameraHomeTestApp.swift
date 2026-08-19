import SwiftUI

@main
struct CameraHomeTestApp: App {
    @State private var coordinator = AppCoordinator()
    @State private var progressController = ProgressController()

    private let container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            AppRootView(container: container)
                .environment(coordinator)
                .environment(progressController)
                .preferredColorScheme(.dark)
        }
    }
}
