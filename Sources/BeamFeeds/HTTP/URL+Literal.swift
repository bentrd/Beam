import Foundation

extension URL {
    /// For addresses written out in this lane's source (the catalog, API endpoints). A typo in one is a programming
    /// error, and `check-feeds` loads every one of them, so it cannot reach a user.
    init(literal: StaticString) {
        guard let url = URL(string: "\(literal)") else { preconditionFailure("Invalid URL literal: \(literal)") }
        self = url
    }

    /// The host without a leading "www.", lowercased: what people call the site.
    var bareHost: String? {
        guard let host = host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Path components without the "/" entries `pathComponents` includes.
    var pathSegments: [String] { pathComponents.filter { $0 != "/" } }

    /// The same address with one query item set, replacing any existing item of that name.
    func settingQueryItem(_ name: String, to value: String) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else { return self }
        var items = (components.queryItems ?? []).filter { $0.name != name }
        items.append(URLQueryItem(name: name, value: value))
        components.queryItems = items
        return components.url ?? self
    }
}
