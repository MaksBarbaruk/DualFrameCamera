import Foundation

nonisolated extension NSLock {
    func synchronized<Value>(_ operation: () -> Value) -> Value {
        lock()
        defer { unlock() }
        return operation()
    }
}
