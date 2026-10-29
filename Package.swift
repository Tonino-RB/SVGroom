// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SVGroom",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SVGroomCore"),
        .executableTarget(name: "SVGroom", dependencies: ["SVGroomCore"]),
        .testTarget(name: "SVGroomCoreTests", dependencies: ["SVGroomCore"]),
    ],
    swiftLanguageModes: [.v5]
)
