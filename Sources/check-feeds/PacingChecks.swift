import BeamFeeds
import BeamModels
import Foundation

func checkPacing(_ report: inout CheckReport) async {
    report.section("arXiv pacing (injected clock)")
    let clock = FakeClock()
    let gate = HostGate(minimumInterval: 3, clock: clock.pacing)
    let origin = clock.now
    let starts = Recorder<TimeInterval>()
    let fetch: HTTPFetch = { request in
        starts.append(clock.now - origin)
        return HTTPResponse(url: request.url, status: 200)
    }
    let request = HTTPRequest(url: HackerNews.feedURL)
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<4 { group.addTask { _ = try? await gate.send(request, using: fetch, patience: 60) } }
    }
    report.expectEqual(starts.values.sorted(), [0, 3, 6, 9], "four requests fired together leave 3 s apart")
    report.note("request times on the injected clock: \(starts.values.sorted().map { "\(Int($0)) s" }.joined(separator: ", "))")

    let refused = Recorder<Bool>()
    do { _ = try await gate.send(request, using: fetch, patience: 1) } catch { refused.append(error as? FeedError == .rateLimited(retryAfter: 3)) }
    report.expect(refused.values == [true] && starts.values.count == 4, "a caller with 1 s of patience is turned away at once, and no request leaves")

    report.section("Reddit: Retry-After and rate-limit headers")
    let redditClock = FakeClock()
    let reddit = HostGate(minimumInterval: 2, clock: redditClock.pacing)
    let answers = Recorder<Int>()
    let throttled: HTTPFetch = { request in
        answers.append(0)
        return answers.values.count == 1
            ? HTTPResponse(url: request.url, status: 429, headers: ["Retry-After": "7"])
            : HTTPResponse(url: request.url, status: 200, headers: ["x-ratelimit-remaining": "0.0", "x-ratelimit-reset": "41"])
    }
    let response = try? await reddit.send(request, using: throttled, patience: 120)
    report.expect(response?.status == 200 && answers.values.count == 2 && redditClock.sleeps == [7], "429 with Retry-After: 7 is slept through, then retried once", detail: "\(redditClock.sleeps)")

    var impatient: FeedError?
    do { _ = try await reddit.send(request, using: throttled, patience: 4) } catch { impatient = error as? FeedError }
    report.expect(impatient == .rateLimited(retryAfter: 41) && answers.values.count == 2, "X-Ratelimit-Remaining: 0 closes the gate for the 41 s the host named", detail: "\(String(describing: impatient))")
    _ = try? await reddit.send(request, using: throttled, patience: 120)
    report.expect(redditClock.sleeps == [7, 41] && answers.values.count == 3, "a patient caller waits out those 41 s, then goes", detail: "\(redditClock.sleeps)")

    let overlap = MockWeb()
    overlap.serve(HackerNews.feedURL.absoluteString) { request in
        try await Task.sleep(nanoseconds: 20_000_000)
        return HTTPResponse(url: request.url, status: 200)
    }
    let serial = HostGate(minimumInterval: 0, clock: FakeClock().pacing)
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<5 { group.addTask { _ = try? await serial.send(request, using: overlap.fetch, patience: 60) } }
    }
    report.expect(overlap.requests.count == 5 && overlap.peakConcurrency == 1, "requests through one gate never overlap", detail: "peak \(overlap.peakConcurrency)")
}

/// A thread-safe list for closures that run on other tasks.
final class Recorder<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Value] = []
    var values: [Value] { lock.withLock { stored } }
    func append(_ value: Value) { lock.withLock { stored.append(value) } }
}
