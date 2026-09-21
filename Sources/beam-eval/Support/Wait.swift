import BeamEngine
import BeamModels
import Foundation

/// Everything a snapshot stream said, and when it said it.
///
/// The timings are the point: "the first found row under 1.5 s" and "settled under 3 s" are promises about
/// snapshots, not about requests.
@MainActor
final class Trace<T> {
    private let start = ContinuousClock.now
    private(set) var stamps: [(at: Duration, value: T)] = []

    func append(_ value: T) { stamps.append((ContinuousClock.now - start, value)) }

    var values: [T] { stamps.map(\.value) }
    var last: T? { stamps.last?.value }
    var count: Int { stamps.count }

    /// When the first snapshot that satisfies `condition` arrived, or nil if none did.
    func first(_ condition: (T) -> Bool) -> Duration? {
        stamps.first { condition($0.value) }?.at
    }
}

@MainActor
enum Wait {
    /// Collects a stream until it says what it was waited for, or until the time is up.
    static func collect<T: Sendable>(_ stream: AsyncStream<T>, until done: @escaping @MainActor (T) -> Bool,
                                     within limit: Duration = .seconds(30)) async -> Trace<T> {
        let trace = Trace<T>()
        let work = Task { @MainActor in
            for await value in stream {
                trace.append(value)
                if done(value) { break }
            }
        }
        let watchdog = Task {
            try? await Task.sleep(for: limit)
            work.cancel()
        }
        await work.value
        watchdog.cancel()
        return trace
    }

    /// Runs a list to the end of its run.
    static func list(_ engine: Engine, _ request: ListRequest, within limit: Duration = .seconds(30)) async -> Trace<ListSnapshot> {
        await collect(engine.list(request), until: { !$0.isRunning }, within: limit)
    }

    /// Opens an article and waits until it has been read and judged (or found to be unreadable).
    static func reader(_ engine: Engine, itemID: Int64, carrying sentence: String? = nil,
                       within limit: Duration = .seconds(30)) async -> Trace<ReaderSnapshot> {
        await collect(engine.open(itemID: itemID, carrying: sentence),
                      until: { $0.phase != .loading && !$0.isRunning }, within: limit)
    }

    /// Waits for something that is not a stream, such as a background pass over the pins.
    static func until(_ condition: @MainActor () -> Bool, within limit: Duration = .seconds(30)) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    /// Something a collecting closure can remember, since it may only do what the main actor may do.
    @MainActor
    final class Flag {
        var isSet = false
        func set() -> Bool {
            defer { isSet = true }
            return isSet
        }
    }

    static func milliseconds(_ duration: Duration?) -> String {
        guard let duration else { return "never" }
        return "\(Int(duration.components.seconds * 1_000 + duration.components.attoseconds / 1_000_000_000_000_000)) ms"
    }
}
