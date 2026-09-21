import BeamFeeds
import Foundation

/// A canned internet: answers by exact URL, 404 for everything else, and remembers what it was asked.
final class MockWeb: @unchecked Sendable {
    typealias Responder = @Sendable (HTTPRequest) async throws -> HTTPResponse

    private let lock = NSLock()
    private var responders: [String: Responder] = [:]
    private var log: [HTTPRequest] = []
    private var inFlight = 0
    private var peak = 0

    var requests: [HTTPRequest] { lock.withLock { log } }
    var requestedURLs: [String] { requests.map(\.url.absoluteString) }
    /// The most requests that were ever being answered at the same moment.
    var peakConcurrency: Int { lock.withLock { peak } }

    func serve(_ url: String, status: Int = 200, headers: [String: String] = [:], body: String = "") {
        serve(url) { request in HTTPResponse(url: request.url, status: status, headers: headers, body: Data(body.utf8)) }
    }

    func serve(_ url: String, _ responder: @escaping Responder) {
        lock.withLock { responders[url] = responder }
    }

    var fetch: HTTPFetch {
        { [self] request in
            let responder: Responder? = lock.withLock {
                log.append(request)
                inFlight += 1
                peak = max(peak, inFlight)
                return responders[request.url.absoluteString]
            }
            defer { lock.withLock { inFlight -= 1 } }
            guard let responder else { return HTTPResponse(url: request.url, status: 404) }
            return try await responder(request)
        }
    }
}

/// Time that only moves when someone sleeps, so three seconds of pacing take no time to check.
final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: TimeInterval = 1_000
    private var naps: [TimeInterval] = []

    var now: TimeInterval { lock.withLock { time } }
    var sleeps: [TimeInterval] { lock.withLock { naps } }

    var pacing: PacingClock {
        PacingClock(now: { [self] in now }, sleep: { [self] duration in
            lock.withLock { time += duration; naps.append(duration) }
        })
    }
}
