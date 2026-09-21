import Foundation

/// The real transport: one ephemeral `URLSession` shared by refreshing and resolving.
public enum HTTPClient {
    /// A hard ceiling per request. A feed that has not arrived by then is reported as failing, not waited on.
    public static let timeout: TimeInterval = 15

    /// Says who is asking. Reddit throttles anonymous-looking clients hardest (EVIDENCE.md), and a named reader
    /// is what feed publishers expect to see in their logs.
    public static let userAgent = "Beam/1.0 (macOS feed reader; dev.beam.app)"

    public static let live: HTTPFetch = { request in
        var urlRequest = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        do {
            let (body, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw FeedError.network("the server didn't answer over HTTP") }
            var headers: [String: String] = [:]
            for (name, value) in http.allHeaderFields {
                if let name = name as? String, let value = value as? String { headers[name] = value }
            }
            return HTTPResponse(url: http.url ?? request.url, status: http.statusCode, headers: headers, body: body)
        } catch {
            throw try FeedError.wrapping(error)
        }
    }

    /// No cookies, no disk, no URL cache: conditional GET is done by hand in `Refresher`, and a transparent cache
    /// would hide the 304s it relies on.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: configuration)
    }()
}

enum Accept {
    static let feed = "application/atom+xml, application/rss+xml, application/rdf+xml;q=0.9, application/xml;q=0.8, text/xml;q=0.8, */*;q=0.5"
    static let page = "text/html, application/xhtml+xml, application/atom+xml;q=0.9, application/rss+xml;q=0.9, */*;q=0.5"
    static let json = "application/json"
}
