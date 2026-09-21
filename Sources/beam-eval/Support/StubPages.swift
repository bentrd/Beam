import BeamExtract
import Foundation

/// The web, as far as article pages are concerned. Saved pages answer for real addresses, so the reader can be
/// checked end to end — fetch, decode, extract, judge — with nothing but files.
final class StubPages: PageFetching, @unchecked Sendable {
    private struct Page {
        var bytes: Data
        var charset: String?
        var contentType: String
    }

    private let lock = NSLock()
    private var pages: [String: Page] = [:]
    private var asked: [String] = []

    init() {}

    var requests: Int { lock.withLock { asked.count } }
    func reset() { lock.withLock { asked.removeAll() } }

    func serve(_ address: String, html: String, charset: String? = "utf-8") {
        serve(address, bytes: Data(html.utf8), charset: charset)
    }

    func serve(_ address: String, bytes: Data, charset: String? = "utf-8", contentType: String = "text/html") {
        lock.withLock { pages[address] = Page(bytes: bytes, charset: charset, contentType: contentType) }
    }

    func fetch(_ url: URL) async throws -> FetchedPage {
        let page: Page? = lock.withLock {
            asked.append(url.absoluteString)
            return pages[url.absoluteString]
        }
        guard let page else { throw FetchFailure.http(status: 404) }
        return FetchedPage(url: url, data: page.bytes, contentType: page.contentType, charset: page.charset)
    }
}
