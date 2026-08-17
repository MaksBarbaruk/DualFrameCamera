import Foundation
import Testing
@testable import CameraHomeTest

@MainActor
struct AppCoordinatorTests {
    @Test
    func selectingTabClearsDetailPath() {
        let coordinator = AppCoordinator()
        coordinator.showCapture(id: UUID())

        coordinator.select(.feed)

        #expect(coordinator.selectedTab == .feed)
        #expect(coordinator.path.isEmpty)
    }

    @Test
    func navigateBackRemovesOnlyLatestRoute() {
        let coordinator = AppCoordinator()
        coordinator.showCapture(id: UUID())
        coordinator.showCapture(id: UUID())

        coordinator.navigateBack()

        #expect(coordinator.path.count == 1)
    }
}
