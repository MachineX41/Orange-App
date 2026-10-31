// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Orange",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "OrangeKit", targets: ["OrangeKit"]),
        .executable(name: "Orange", targets: ["Orange"])
    ],
    dependencies: [
        .package(url: "https://github.com/SDWebImage/libwebp-Xcode.git", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "OrangeKit",
            dependencies: [.product(name: "libwebp", package: "libwebp-Xcode")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Orange",
            dependencies: ["OrangeKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "OrangeKitTests",
            dependencies: ["OrangeKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
