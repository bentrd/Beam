import BeamModels
import BeamStore
import Darwin
import Foundation

/// Runs one area. A thrown error is a failed check, not a crash, so the remaining areas still report.
func run(_ title: String, _ report: inout CheckReport, _ body: (inout CheckReport) async throws -> Void) async {
    report.section(title)
    do {
        try await body(&report)
    } catch {
        report.expect(false, "\(title): ran to the end", detail: "\(error)")
    }
}

extension CheckReport {
    /// `expect` for a value that had to be awaited: its autoclosure cannot contain `await`.
    mutating func expectTrue(_ value: Bool, _ what: String) {
        expect(value, what)
    }
}

/// The error an operation throws, or nil when it succeeds.
func failure(of work: () async throws -> Void) async -> StoreError? {
    do {
        try await work()
        return nil
    } catch let error as StoreError {
        return error
    } catch {
        return .invalid("unexpected error type: \(error)")
    }
}

/// Wall-clock milliseconds.
func milliseconds(_ work: () async throws -> Void) async rethrows -> Double {
    let start = DispatchTime.now().uptimeNanoseconds
    try await work()
    return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}

/// The slowest of several runs, the first (cold statement, cold page cache) included: the honest number for a 50 ms promise.
func slowest(of runs: Int, _ work: () async throws -> Void) async rethrows -> Double {
    var worst = 0.0
    for _ in 0..<runs { worst = max(worst, try await milliseconds(work)) }
    return worst
}

struct TemporaryFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("beam-check-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func file(_ name: String) -> URL { url.appendingPathComponent(name) }

    func remove() { try? FileManager.default.removeItem(at: url) }
}

enum Memory {
    /// Pages resident right now.
    static var residentBytes: UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        return status == KERN_SUCCESS ? info.resident_size : 0
    }

    /// The most that was ever resident during the run (bytes on macOS).
    static var peakResidentBytes: UInt64 {
        var usage = rusage()
        return getrusage(RUSAGE_SELF, &usage) == 0 ? UInt64(max(usage.ru_maxrss, 0)) : 0
    }

    static func megabytes(_ bytes: UInt64) -> String { String(format: "%.1f MB", Double(bytes) / 1_048_576) }
}
