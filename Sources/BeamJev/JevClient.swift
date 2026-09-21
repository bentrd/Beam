import Foundation

/// A thin, retrying client for TypeSafe's System One endpoint. It knows HTTP and nothing about Beam:
/// the key arrives with each call (it can change while the app runs), and limits and spend live in `Judge`.
public struct JevClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    public typealias Pause = @Sendable (TimeInterval) async throws -> Void

    public static let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
    /// "jev-latest" follows releases; the concrete id comes back with each answer and keys the cache.
    public static let defaultModel = "jev-latest"
    /// 429, 529, 5xx and transport hiccups: five tries, waiting 0.4 s, 0.8 s, 1.6 s, 3.2 s between them.
    public static let tries = 5
    public static let firstDelay: TimeInterval = 0.4

    /// One session for the whole process, so every request rides the same HTTP/2 connection (URLSession negotiates it)
    /// instead of paying a TLS handshake each. Ephemeral: titles and paragraphs are never cached or cookied on disk.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpMaximumConnectionsPerHost = 64
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    /// With no connection a retry cannot help, and five of them would hold "Offline" back by six seconds.
    private static let offlineCodes: Set<URLError.Code> = [.notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff]

    private let model: String
    private let transport: Transport
    private let pause: Pause

    /// `transport` and `pause` exist so the checks can replay 429s and malformed bodies without the network or the wait.
    public init(model: String = JevClient.defaultModel, transport: Transport? = nil, pause: Pause? = nil) {
        self.model = model
        self.transport = transport ?? { request in try await JevClient.session.data(for: request) }
        self.pause = pause ?? { seconds in try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    }

    /// One request: one piece of state, every frame as a parallel Noul. Packing several items into one
    /// request was measured and rejected (quality drops), so `state` is always a single item or passage.
    public func ask(key: String, state: [String: String], frames: [String]) async throws -> Judgments {
        guard !key.isEmpty else { throw JevError.missingKey }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Wire.body(model: model, state: state, frames: frames)

        var delay = Self.firstDelay
        var failure = JevError.overloaded(status: 0)
        for attempt in 1...Self.tries {
            try Task.checkCancellation()
            switch try await send(request, frameCount: frames.count, redacting: key) {
            case let .answered(judgments): return judgments
            case let .retry(after): failure = after
            }
            guard attempt < Self.tries else { break }
            // A little jitter, so 64 requests refused together do not all come back together.
            try await pause(delay * Double.random(in: 1...1.25))
            delay *= 2
        }
        throw failure
    }

    private enum Attempt {
        case answered(Judgments)
        case retry(JevError)
    }

    private func send(_ request: URLRequest, frameCount: Int, redacting key: String) async throws -> Attempt {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            // URLSession reports a cancelled task its own way; callers should see one kind of cancellation.
            throw CancellationError()
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw JevError.unreachable(error.localizedDescription)
        } catch {
            return .retry(.unreachable(error.localizedDescription))
        }

        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw JevError.malformedResponse }
        switch status {
        case 200:
            return .answered(try Wire.judgments(from: data, frameCount: frameCount))
        case 401, 403:
            throw JevError.unauthorized
        case 429, 500...599:
            return .retry(.overloaded(status: status))
        default:
            let detail = String(decoding: data.prefix(300), as: UTF8.self).replacingOccurrences(of: key, with: "<key>")
            throw JevError.rejected(status: status, detail: detail)
        }
    }
}
