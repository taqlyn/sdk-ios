// swift-tools-version: 5.9
import Foundation
import PackageDescription

// Published `taqlyn/sdk-ios` must not require a sibling checkout.
// Nav integration tests run only in the platform monorepo.
let localNav = "../nav-swiftui"
let hasLocalNav = FileManager.default.fileExists(atPath: localNav + "/Package.swift")

var packageDependencies: [Package.Dependency] = []
var extraTargets: [Target] = []
if hasLocalNav {
    packageDependencies.append(.package(path: localNav))
    extraTargets.append(
        .testTarget(
            name: "TaqlynSDKNavIntegrationTests",
            dependencies: [
                "TaqlynSDK",
                .product(name: "TaqlynNavSwiftUI", package: "nav-swiftui"),
            ],
            path: "Tests/TaqlynSDKNavIntegrationTests"
        )
    )
}

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
    dependencies: packageDependencies,
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
    ] + extraTargets
)
