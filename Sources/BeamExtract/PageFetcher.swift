import Foundation

/// The bytes of one downloaded page and what the server said about them.
public struct FetchedPage: Sendable {
    /// The address after redirects.
    public var url: URL
    public var data: Data
    /// The `Content-Type` header, verbatim, when the server sent one.
    public var contentType: String?
    /// The charset named by the HTTP headers: the first thing `TextDecoder` trusts.
    public var charset: String?

    public init(url: URL, data: Data, contentType: String? = nil, charset: String? = nil) {
        self.url = url; self.data = data; self.contentType = contentType; self.charset = charset
    }
}

/// Why a page could not be downloaded. The description ends up in `ArticleContent.unavailable(reason:)`.
public enum FetchFailure: Error, Equatable, CustomStringConvertible {
    case http(status: Int)
    case notHTML(contentType: String)
    case tooLarge
    case transport(String)

    public var description: String {
        switch self {
        case let .http(status): return "HTTP \(status)"
        case let .notHTML(contentType): return "Not a web page (\(contentType))"
        case .tooLarge: return "The page is larger than \(Readability.maximumBytes / 1_048_576) MB"
        case let .transport(message): return message
        }
    }
}

/// The seam that lets `ArticleLoader` be checked against saved pages without a network.
public protocol PageFetching: Sendable {
    func fetch(_ url: URL) async throws -> FetchedPage
}

/// Downloads one page the way PRODUCT.md section 6 prescribes: an ephemeral session, a Safari User-Agent, 15 seconds.
///
/// Every fetch gets its own session, so no cookie or cache entry from one article can follow the reader to the next.
/// The download stops as soon as the headers show an error, something that is not HTML (a PDF or a video linked from
/// Hacker News is never pulled down), or a body over `Readability.maximumBytes`.
public struct PageFetcher: PageFetching {
    public static let timeout: TimeInterval = 15
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    public init() {}

    public func fetch(_ url: URL) async throws -> FetchedPage {
        do {
            return try await download(url)
        } catch is InsecureConnectionRefused {
            // Inside the app bundle, App Transport Security refuses plain http. Old links usually work over https.
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw FetchFailure.transport("The link is not secure") }
            components.scheme = "https"
            guard let secure = components.url else { throw FetchFailure.transport("The link is not secure") }
            do { return try await download(secure) } catch is InsecureConnectionRefused { throw FetchFailure.transport("The link is not secure") }
        }
    }

    private func download(_ url: URL) async throws -> FetchedPage {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.timeout
        configuration.timeoutIntervalForResource = Self.timeout
        configuration.httpAdditionalHeaders = [
            "User-Agent": Self.userAgent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        ]
        let download = CappedDownload(limit: Readability.maximumBytes)
        let session = URLSession(configuration: configuration, delegate: download, delegateQueue: nil)
        // The session keeps its delegate alive until it is invalidated; this lets the running task finish first.
        defer { session.finishTasksAndInvalidate() }

        let task = session.dataTask(with: url)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                download.start(task, continuation: continuation)
            }
        } onCancel: {
            task.cancel()
        }
    }
}

/// App Transport Security blocked a plain-http load; `PageFetcher` answers by trying https once.
private struct InsecureConnectionRefused: Error {}

/// Collects a response body up to a limit. All callbacks arrive on the session's serial delegate queue, which is
/// what makes the unsynchronised state safe.
private final class CappedDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let limit: Int
    private var body = Data()
    private var response: HTTPURLResponse?
    private var failure: FetchFailure?
    private var continuation: CheckedContinuation<FetchedPage, Error>?

    init(limit: Int) { self.limit = limit }

    func start(_ task: URLSessionDataTask, continuation: CheckedContinuation<FetchedPage, Error>) {
        self.continuation = continuation
        task.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else { failure = .transport("Not an HTTP response"); return completionHandler(.cancel) }
        self.response = http
        let contentType = http.value(forHTTPHeaderField: "Content-Type")
        if !(200..<300).contains(http.statusCode) { failure = .http(status: http.statusCode) }
        else if let contentType, !contentType.lowercased().contains("html") { failure = .notHTML(contentType: contentType) }
        else if http.expectedContentLength > Int64(limit) { failure = .tooLarge }
        completionHandler(failure == nil ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        body.append(data)
        if body.count > limit { failure = .tooLarge; dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { continuation = nil }
        if let failure { continuation?.resume(throwing: failure); return }
        if let error {
            switch (error as? URLError)?.code {
            case .cancelled: continuation?.resume(throwing: CancellationError())
            case .appTransportSecurityRequiresSecureConnection: continuation?.resume(throwing: InsecureConnectionRefused())
            default: continuation?.resume(throwing: FetchFailure.transport(error.localizedDescription))
            }
            return
        }
        guard let response, let url = response.url else { continuation?.resume(throwing: FetchFailure.transport("No response")); return }
        continuation?.resume(returning: FetchedPage(url: url, data: body, contentType: response.value(forHTTPHeaderField: "Content-Type"),
                                                     charset: response.textEncodingName))
    }
}
