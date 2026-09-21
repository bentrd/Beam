import Foundation

/// What a page says about itself when its text turns out thin, so the failure can be named (for logs and help tags;
/// the reader always shows the same calm sentence).
struct PageSignals: Equatable {
    /// The publisher declares the article is not free to read (schema.org `isAccessibleForFree: false`, the
    /// markup Google asks paywalled sites to carry, or Open Graph's `article:content_tier`).
    let declaresPaywall: Bool
    /// The page asks for JavaScript in a `<noscript>` or is an empty application shell.
    let needsJavaScript: Bool

    private static let paywall = NSRegularExpression.builtIn(#""isAccessibleForFree"\s*:\s*"?false|content_tier"\s+content\s*=\s*"(?:locked|metered)"#)
    private static let noscriptPlea = NSRegularExpression.builtIn(#"<noscript\b[^>]*>[\s\S]{0,2000}?(?:enable|requires?|activer|without)\s+javascript"#)
    private static let emptyShell = NSRegularExpression.builtIn(#"<div\b[^>]*\bid\s*=\s*["'](?:root|app|__next|__nuxt|react-root)["'][^>]*>\s*</div>"#)

    init(html: String) {
        let range = NSRange(location: 0, length: (html as NSString).length)
        declaresPaywall = Self.paywall.firstMatch(in: html, range: range) != nil
        needsJavaScript = Self.noscriptPlea.firstMatch(in: html, range: range) != nil || Self.emptyShell.firstMatch(in: html, range: range) != nil
    }
}
