import BeamFeeds
import BeamModels
import Foundation

/// The web, as far as feeds are concerned: a handful of addresses that answer with what a check put there.
///
/// It counts requests, so a check can show that clicking a source or repeating a search touches nothing, and it
/// can change what an address answers between refreshes, which is how "one edited title costs one more request"
/// is put to the test.
final class StubWeb: @unchecked Sendable {
    private struct Page {
        var status: Int
        var contentType: String
        var body: Data
    }

    private let lock = NSLock()
    private var pages: [String: Page] = [:]
    private var asked: [String] = []

    init() {}

    var requests: Int { lock.withLock { asked.count } }
    var addresses: [String] { lock.withLock { asked } }
    func reset() { lock.withLock { asked.removeAll() } }

    func serve(_ address: String, _ body: String, contentType: String = "application/rss+xml; charset=utf-8", status: Int = 200) {
        lock.withLock { pages[address] = Page(status: status, contentType: contentType, body: Data(body.utf8)) }
    }

    func serve(_ address: String, bytes: Data, contentType: String) {
        lock.withLock { pages[address] = Page(status: 200, contentType: contentType, body: bytes) }
    }

    var fetch: HTTPFetch {
        { [weak self] request in
            guard let self else { throw FeedError.network("the stub is gone") }
            let address = request.url.absoluteString
            let page: Page? = self.lock.withLock {
                self.asked.append(address)
                return self.pages[address]
            }
            guard let page else {
                // Nothing at that address: the same thing the real web says, so the resolver's fallbacks are exercised.
                return HTTPResponse(url: request.url, status: 404, headers: ["Content-Type": "text/html"], body: Data())
            }
            return HTTPResponse(url: request.url, status: page.status, headers: ["Content-Type": page.contentType], body: page.body)
        }
    }
}
