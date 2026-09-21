import Foundation

/// One GET. Feeds never need a body or another verb, so the request stays this small and a test can build one by hand.
public struct HTTPRequest: Sendable, Hashable {
    public var url: URL
    public var headers: [String: String]

    public init(url: URL, headers: [String: String] = [:]) {
        self.url = url
        self.headers = headers
    }
}

/// What came back, whatever the status: deciding what a 304, a 404 or a 429 means is the caller's job, not the transport's.
public struct HTTPResponse: Sendable {
    /// The address after redirects. Relative links in the body resolve against this, not against what was asked for.
    public var url: URL
    public var status: Int
    public var body: Data
    private var headers: [String: String]

    public init(url: URL, status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.url = url
        self.status = status
        self.body = body
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    /// Header names are case-insensitive on the wire and HTTP/2 lowercases them, so lookups must not care.
    public func header(_ name: String) -> String? { headers[name.lowercased()] }

    /// The `charset` parameter of Content-Type, if the server sent one.
    public var charset: String? {
        guard let type = header("Content-Type") else { return nil }
        for parameter in type.split(separator: ";").dropFirst() {
            let pair = parameter.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pair.count == 2, pair[0].lowercased() == "charset" {
                return pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return nil
    }

    public var isSuccess: Bool { (200..<300).contains(status) }
}

/// The seam every network call in this lane goes through, so checks run against canned responses and
/// the engine can swap the transport without touching parsing or resolving.
/// Implementations throw `FeedError` for transport failures and return normally for any HTTP status.
public typealias HTTPFetch = @Sendable (HTTPRequest) async throws -> HTTPResponse
