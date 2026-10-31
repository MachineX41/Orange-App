// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Orange",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "OrangeKit", targets: ["OrangeKit"]),
        .executable(name: "Orange", targets: ["Orange"])
    ],
    targets: [
        .target(name: "OrangeKit"),
        .executableTarget(
            name: "Orange",
            dependencies: ["OrangeKit"]
        ),
        .testTarget(
            name: "OrangeKitTests",
            dependencies: ["OrangeKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)
