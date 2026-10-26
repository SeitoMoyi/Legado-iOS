import SwiftUI

/// Owns work started by one reader presentation. Leaving invalidates results immediately,
/// even when a source or a network callback takes time to observe cancellation.
@MainActor
final class ReaderLoadSession: ObservableObject {
    struct Ticket: Equatable {
        let key: String
        let id = UUID()
    }

    private struct Pending {
        let ticket: Ticket
        let cancel: () -> Void
    }

    private var pending: [String: Pending] = [:]
    private(set) var isActive = true

    nonisolated init() {}

    func accepts(_ ticket: Ticket) -> Bool {
        isActive && !Task.isCancelled && pending[ticket.key]?.ticket == ticket
    }

    func start(_ key: String, operation: @escaping (Ticket) async -> Void) {
        guard isActive else { return }
        cancel(key)
        let ticket = Ticket(key: key)
        let task = Task {
            guard accepts(ticket) else { return }
            await operation(ticket)
            finish(ticket)
        }
        pending[key] = Pending(ticket: ticket, cancel: { task.cancel() })
    }

    /// For canvas requests whose caller needs a result. Cancellation reaches the underlying
    /// URLSession request, rather than just abandoning the task waiting for its value.
    func value<Value>(_ key: String, operation: @escaping () async throws -> Value) async throws -> Value {
        guard isActive, !Task.isCancelled else { throw CancellationError() }
        cancel(key)
        let ticket = Ticket(key: key)
        let task = Task {
            try Task.checkCancellation()
            return try await operation()
        }
        pending[key] = Pending(ticket: ticket, cancel: { task.cancel() })
        defer { finish(ticket) }
        return try await withTaskCancellationHandler {
            let result = try await task.value
            guard accepts(ticket) else { throw CancellationError() }
            return result
        } onCancel: {
            task.cancel()
        }
    }

    func cancel(_ key: String) {
        pending.removeValue(forKey: key)?.cancel()
    }

    func cancelPending() {
        let requests = pending.values
        pending.removeAll()
        for request in requests { request.cancel() }
    }

    func stop() {
        isActive = false
        cancelPending()
    }

    private func finish(_ ticket: Ticket) {
        if pending[ticket.key]?.ticket == ticket { pending.removeValue(forKey: ticket.key) }
    }
}
