import Foundation
import Observation

nonisolated enum AppTab: String, CaseIterable, Hashable, Identifiable, Sendable {
    case camera
    case feed

    var id: Self { self }

    var title: String {
        switch self {
        case .camera: "Camera"
        case .feed: "Moments"
        }
    }

    var systemImage: String {
        switch self {
        case .camera: "camera.fill"
        case .feed: "square.grid.2x2.fill"
        }
    }
}

nonisolated enum AppRoute: Hashable, Sendable {
    case captureDetail(UUID)
}

@MainActor
@Observable
final class AppCoordinator {
    var selectedTab: AppTab = .camera
    var path: [AppRoute] = []
    private(set) var feedRevision = 0

    func select(_ tab: AppTab) {
        selectedTab = tab
        path.removeAll()
    }

    func showCapture(id: UUID) {
        path.append(.captureDetail(id))
    }

    func presentSavedCapture(id: UUID) {
        feedRevision += 1
        selectedTab = .feed
        path = [.captureDetail(id)]
    }

    func navigateBack() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func navigateToRoot() {
        path.removeAll()
    }
}
