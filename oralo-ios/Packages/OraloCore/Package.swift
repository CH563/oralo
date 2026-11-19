// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OraloCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "OraloCore", targets: ["OraloCore"])],
    targets: [
        .target(name: "OraloCore"),
        .testTarget(name: "OraloCoreTests", dependencies: ["OraloCore"])
    ]
)
