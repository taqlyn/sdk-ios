// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TaqlynSDK",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "TaqlynSDK",
            targets: ["TaqlynSDK"]
        ),
    ],
    dependencies: [
        .package(path: "../nav-swiftui"),
    ],
    targets: [
        .target(
            name: "TaqlynSDK",
            path: "Sources/TaqlynSDK",
            resources: [
                .copy("PrivacyInfo.xcprivacy"),
            ]
        ),
        .testTarget(
            name: "TaqlynSDKTests",
            dependencies: ["TaqlynSDK"],
            path: "Tests/TaqlynSDKTests"
        ),
        .testTarget(
            name: "TaqlynSDKNavIntegrationTests",
            dependencies: [
                "TaqlynSDK",
                .product(name: "TaqlynNavSwiftUI", package: "nav-swiftui"),
            ],
            path: "Tests/TaqlynSDKNavIntegrationTests"
        ),
    ]
)
