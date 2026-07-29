// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "yd-ebike-helper",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "yd-ebike-helper",
            targets: ["YDEbikeHelper"]
        )
    ],
    targets: [
        .executableTarget(
            name: "YDEbikeHelper",
            path: "Sources/YDEbikeHelper"
        ),
        .testTarget(
            name: "YDEbikeHelperTests",
            dependencies: ["YDEbikeHelper"],
            path: "Tests/YDEbikeHelperTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
