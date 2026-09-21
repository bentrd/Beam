// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "JevKit",
    platforms: [.macOS(.v26)],
    products: [.library(name: "JevKit", targets: ["JevKit"])],
    targets: [
        .target(name: "JevKit", path: "Sources/JevKit"),
        .executableTarget(name: "jevprobe", dependencies: ["JevKit"], path: "Sources/jevprobe"),
        .executableTarget(name: "pdfprobe", path: "Sources/pdfprobe"),
        .executableTarget(name: "extractprobe", path: "Sources/extractprobe"),
        .executableTarget(name: "readerprobe", path: "Sources/readerprobe"),
        .executableTarget(name: "beamprobe", dependencies: ["JevKit"], path: "Sources/beamprobe"),
        .executableTarget(name: "extracteval", path: "Sources/extracteval"),
        .executableTarget(name: "macroprobe", path: "Sources/macroprobe", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
