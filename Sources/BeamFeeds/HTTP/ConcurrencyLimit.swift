import Foundation

/// Caps how many requests are on the wire at once. Waiting on a host gate does not hold a place, so a queue of
/// paced arXiv sources cannot starve ordinary feeds of connections.
actor ConcurrencyLimit {
    private var free: Int
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(_ limit: Int) { free = max(1, limit) }

    func run<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        await acquire()
        do {
            let value = try await operation()
            release()
            return value
        } catch {
            release()
            throw error
        }
    }

    private func acquire() async {
        if free > 0 { free -= 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty { free += 1 } else { waiting.removeFirst().resume() }
    }
}

/// Fails with `FeedError.timedOut` when `operation` has not finished in time. The transport has its own timeout;
/// this one also covers a transport that was injected and has none.
func withTimeout<T: Sendable>(_ seconds: TimeInterval, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask(operation: operation)
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            throw FeedError.timedOut
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw FeedError.timedOut }
        return first
    }
}
