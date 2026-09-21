import Foundation

/// Where a failure goes that the screen has no sentence for.
///
/// Beam shows errors as one foot sentence and nothing else: no alerts, no banners. A store read that fails or a
/// judgment that cannot be cached has no such sentence, and swallowing it silently would make the next bug
/// invisible. It goes to standard error, where `beam-eval` and Console can see it. Nothing here is user-facing,
/// and nothing here ever carries the key.
enum EngineLog {
    static func failure(_ what: String, _ error: Error) {
        write("beam: \(what): \(error)")
    }

    static func note(_ text: String) {
        write("beam: \(text)")
    }

    private static func write(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
