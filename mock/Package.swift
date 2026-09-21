// swift-tools-version: 6.2
import PackageDescription

// A throwaway design mock: real captured data, no networking, no product logic.
let package = Package(
    name: "BeamMock",
    platforms: [.macOS(.v26)],
    targets: [.executableTarget(name: "BeamMock", path: "Sources/BeamMock", swiftSettings: [.swiftLanguageMode(.v5)])]
)
