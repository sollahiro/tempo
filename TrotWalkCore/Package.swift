// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TrotWalkCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "TrotWalkCore", targets: ["TrotWalkCore"]),
    ],
    targets: [
        .target(name: "TrotWalkCore"),
        .testTarget(name: "TrotWalkCoreTests", dependencies: ["TrotWalkCore"]),
    ]
)
