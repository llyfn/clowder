// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClowderKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ClowderKit", targets: ["ClowderKit"]),
        .executable(name: "smcprobe", targets: ["smcprobe"]),
    ],
    targets: [
        .target(name: "ClowderKit"),
        .executableTarget(name: "smcprobe", dependencies: ["ClowderKit"]),
        .testTarget(name: "ClowderKitTests", dependencies: ["ClowderKit"]),
    ]
)
