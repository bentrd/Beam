import Foundation

/// Publishes at most one snapshot per interval (200 ms for lists, 100 ms for the reader), so 300 answers
/// arriving in a second become five repaints instead of three hundred.
///
/// The last state is never lost: a change that arrives inside the interval wakes a single timer that publishes
/// when it expires. `flush()` publishes at once, which is what a settling run does so the list never ends on a
/// stale snapshot.
@MainActor
final class SnapshotThrottle {
    private let interval: Duration
    private let publish: @MainActor () -> Void
    private var lastPublished: ContinuousClock.Instant?
    private var pending: Task<Void, Never>?

    init(every interval: Duration, publish: @escaping @MainActor () -> Void) {
        self.interval = interval
        self.publish = publish
    }

    /// Something changed. Publishes now if the interval has passed, else schedules one publication for when it has.
    func touch() {
        guard pending == nil else { return }
        let now = ContinuousClock.now
        if let lastPublished, now - lastPublished < interval {
            let wait = interval - (now - lastPublished)
            pending = Task { [weak self] in
                try? await Task.sleep(for: wait)
                guard let self, !Task.isCancelled else { return }
                self.pending = nil
                self.flush()
            }
            return
        }
        lastPublished = now
        publish()
    }

    /// Publishes immediately and starts the interval again. For the first snapshot and for a settled run.
    func flush() {
        pending?.cancel()
        pending = nil
        lastPublished = .now
        publish()
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }
}
