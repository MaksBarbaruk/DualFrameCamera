import Foundation
import Observation

nonisolated struct AppAlert: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
@Observable
final class ProgressController {
    private var operationIDs: Set<UUID> = []

    private(set) var isProcessing = false
    var alert: AppAlert?

    @discardableResult
    func perform<Value: Sendable>(
        title: String = "Something went wrong",
        operation: @escaping @Sendable () async throws -> Value
    ) async -> Value? {
        let operationID = beginOperation()
        defer { endOperation(operationID) }

        do {
            return try await operation()
        } catch is CancellationError {
            return nil
        } catch {
            show(error, title: title)
            return nil
        }
    }

    func show(_ error: Error, title: String = "Something went wrong") {
        alert = AppAlert(title: title, message: error.localizedDescription)
    }

    func show(title: String, message: String) {
        alert = AppAlert(title: title, message: message)
    }

    private func beginOperation() -> UUID {
        let id = UUID()
        operationIDs.insert(id)
        isProcessing = true
        return id
    }

    private func endOperation(_ id: UUID) {
        operationIDs.remove(id)
        isProcessing = !operationIDs.isEmpty
    }
}
