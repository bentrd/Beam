import BeamExtract
import Foundation

/// Serves saved pages in place of the network and remembers what was asked for, so the loader's per-source rules
/// (when it fetches, what it fetches first, what it never fetches) can be checked offline.
final class StubFetcher: PageFetching, @unchecked Sendable {
    enum Response {
        case page(Data, charset: String?)
        case failure(FetchFailure)
    }

    private let lock = NSLock()
    private var responses: [String: Response]
    private var log: [String] = []

    init(_ responses: [String: Response] = [:]) { self.responses = responses }

    var requested: [String] { lock.withLock { log } }

    func fetch(_ url: URL) async throws -> FetchedPage {
        let response = lock.withLock { () -> Response? in
            log.append(url.absoluteString)
            return responses[url.absoluteString]
        }
        switch response {
        case let .page(data, charset): return FetchedPage(url: url, data: data, contentType: "text/html", charset: charset)
        case let .failure(failure): throw failure
        case nil: throw FetchFailure.http(status: 404)
        }
    }
}
