import Foundation

/// The one global cap on requests in flight, shared by search, pins, the reader and pre-judging.
///
/// First come, first served: a new search queues behind what is already waiting rather than starving it,
/// and cancelling the old run empties its place in the queue at once. A slot is handed straight from the
/// task that finishes to the longest waiter, so the count in flight can never pass `capacity`.
public actor Limiter {
    /// Both counts read in one hop, so they describe the same moment.
    public struct Load: Equatable, Sendable {
        /// Slots in use.
        public let held: Int
        /// Tasks queued for a slot.
        public let waiting: Int
        public var isIdle: Bool { held == 0 && waiting == 0 }
    }

    public let capacity: Int
    public var load: Load { Load(held: held, waiting: waiters.count) }

    private var held = 0

    private struct Waiter {
        let ticket: UInt64
        let continuation: CheckedContinuation<Void, Error>
    }
    private var waiters: [Waiter] = []
    private var nextTicket: UInt64 = 0

    public init(capacity: Int) { self.capacity = max(1, capacity) }

    /// Runs `work` once a slot is free and gives the slot back however `work` ends.
    /// Throws `CancellationError` without running `work` if the task is cancelled while it waits.
    public func withSlot<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        try await acquire()
        defer { release() }
        return try await work()
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        if held < capacity {
            held += 1
            return
        }
        let ticket = nextTicket
        nextTicket += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // Cancelled between the check above and here: the handler below has already run and found nothing to remove.
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(ticket: ticket, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.abandon(ticket) }
        }
    }

    /// A cancelled waiter leaves the queue and is told so. If its slot was granted first it is no longer
    /// queued, `acquire` returns normally, and `withSlot` releases as usual: either way nothing leaks.
    private func abandon(_ ticket: UInt64) {
        guard let index = waiters.firstIndex(where: { $0.ticket == ticket }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func release() {
        if waiters.isEmpty {
            held -= 1
        } else {
            // The slot changes hands; `held` does not move.
            waiters.removeFirst().continuation.resume()
        }
    }
}
