// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClowderKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ClowderKit", targets: ["ClowderKit"]),
        .library(name: "SMCCore", targets: ["SMCCore"]),
        .library(name: "HelperProtocol", targets: ["HelperProtocol"]),
        .library(name: "HelperCore", targets: ["HelperCore"]),
        .executable(name: "smcprobe", targets: ["smcprobe"]),
    ],
    targets: [
        .target(name: "SMCCore"),
        .target(name: "HelperProtocol"),
        .target(name: "HelperCore", dependencies: ["HelperProtocol"]),
        .target(name: "ClowderKit", dependencies: ["SMCCore", "HelperProtocol"]),
        .executableTarget(name: "smcprobe", dependencies: ["ClowderKit"]),
        .testTarget(name: "ClowderKitTests", dependencies: ["ClowderKit"]),
        .testTarget(name: "HelperCoreTests", dependencies: ["HelperCore", "HelperProtocol"]),
    ]
)
