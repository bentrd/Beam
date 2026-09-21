import Foundation

/// A tiny assertion harness: this machine has neither XCTest nor Swift Testing.
/// Usage: `var report = CheckReport("feeds"); report.section("Parser"); report.expect(x == 1, "parses one item"); exit(report.finish())`
public struct CheckReport {
    public let name: String
    public private(set) var passed = 0
    public private(set) var failures: [String] = []
    public private(set) var skipped: [String] = []

    public init(_ name: String) { self.name = name; print("== \(name) ==") }

    public func section(_ title: String) { print("\n-- \(title)") }

    public mutating func expect(_ condition: @autoclosure () -> Bool, _ what: String, detail: @autoclosure () -> String = "") {
        if condition() { passed += 1; print("  ok    \(what)") }
        else { let d = detail(); failures.append(what); print("  FAIL  \(what)\(d.isEmpty ? "" : "  [\(d)]")") }
    }

    public mutating func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ what: String) {
        expect(actual == expected, what, detail: "got \(actual), expected \(expected)")
    }

    /// For checks that need the network or a key that is not available right now.
    public mutating func skip(_ what: String, because reason: String) { skipped.append(what); print("  skip  \(what)  (\(reason))") }

    public func note(_ text: String) { print("  ·     \(text)") }

    /// Prints the summary and returns the process exit code.
    public func finish() -> Int32 {
        print("\n\(name): \(passed) passed, \(failures.count) failed, \(skipped.count) skipped")
        for f in failures { print("  failed: \(f)") }
        return failures.isEmpty ? 0 : 1
    }
}

public enum CheckEnvironment {
    /// The TypeSafe key for live checks, from BEAM_KEY then TYPESAFE_API_KEY. Never print it.
    public static var key: String? {
        let env = ProcessInfo.processInfo.environment
        return [env["BEAM_KEY"], env["TYPESAFE_API_KEY"]].compactMap { $0 }.first { !$0.isEmpty }
    }
    public static var isOffline: Bool { CommandLine.arguments.contains("--offline") }
}
