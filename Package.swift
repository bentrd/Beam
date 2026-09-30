// swift-tools-version: 6.2
import PackageDescription

// No Xcode on the build machine: everything here must build with `swift build` alone.
// One library target per lane so parallel builders cannot break each other's builds.
let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Beam",
    platforms: [.macOS(.v26)],
    targets: [
        // The contract: shared value types, UI-facing snapshots, the backend protocol, the check harness.
        .target(name: "BeamModels", path: "Sources/BeamModels", swiftSettings: v5),

        // Engine lanes (no UI imports).
        .target(name: "BeamJev", dependencies: ["BeamModels"], path: "Sources/BeamJev", swiftSettings: v5),
        .target(name: "BeamStore", dependencies: ["BeamModels"], path: "Sources/BeamStore", swiftSettings: v5),
        .target(name: "BeamFeeds", dependencies: ["BeamModels"], path: "Sources/BeamFeeds", swiftSettings: v5),
        .target(name: "BeamExtract", dependencies: ["BeamModels"], path: "Sources/BeamExtract", swiftSettings: v5),
        .target(name: "BeamEngine", dependencies: ["BeamModels", "BeamJev", "BeamStore", "BeamFeeds", "BeamExtract"],
                path: "Sources/BeamEngine", swiftSettings: v5),

        // UI lanes: views talk to `BeamBackend` only, so they run against the fake backend until the engine lands.
        .target(name: "BeamUI", dependencies: ["BeamModels"], path: "Sources/BeamUI",
                resources: [.copy("FakeData")], swiftSettings: v5),
        .executableTarget(name: "Beam", dependencies: ["BeamUI", "BeamEngine", "BeamModels"], path: "Sources/Beam", swiftSettings: v5),
        // Shows ReaderPane alone with captured snapshots (`-scene lit|saturated|loading|unavailable|preview`), so the reader can be reviewed by itself.
        .executableTarget(name: "reader-demo", dependencies: ["BeamUI", "BeamModels"], path: "Sources/reader-demo", swiftSettings: v5),
        // Records app views over captured public content; --live uses the real engine with an isolated library and in-memory credential.
        .executableTarget(name: "beam-demo", dependencies: ["BeamUI", "BeamModels", "BeamEngine", "BeamJev", "BeamFeeds", "BeamStore"], path: "Sources/beam-demo", swiftSettings: v5),

        // Checks (there is no XCTest or Swift Testing here): exit code 0 means green.
        .executableTarget(name: "check-jev", dependencies: ["BeamJev", "BeamModels"], path: "Sources/check-jev", swiftSettings: v5),
        .executableTarget(name: "check-store", dependencies: ["BeamStore", "BeamModels"], path: "Sources/check-store", swiftSettings: v5),
        .executableTarget(name: "check-feeds", dependencies: ["BeamFeeds", "BeamModels"], path: "Sources/check-feeds", swiftSettings: v5),
        .executableTarget(name: "check-extract", dependencies: ["BeamExtract", "BeamModels"], path: "Sources/check-extract",
                          resources: [.copy("Fixtures")], swiftSettings: v5),
        .executableTarget(name: "beam-eval", dependencies: ["BeamEngine", "BeamModels", "BeamJev", "BeamStore", "BeamFeeds", "BeamExtract"],
                          path: "Sources/beam-eval", resources: [.copy("Fixtures")], swiftSettings: v5),
    ]
)
