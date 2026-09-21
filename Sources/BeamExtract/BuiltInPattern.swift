import Foundation

extension NSRegularExpression {
    /// Compiles one of BeamExtract's own case-insensitive patterns. They are compile-time constants, so a failure is a
    /// programming error (caught by the first run of `check-extract`), never something a web page can cause.
    static func builtIn(_ pattern: String) -> NSRegularExpression {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            preconditionFailure("Invalid built-in pattern: \(pattern)")
        }
        return regex
    }
}
