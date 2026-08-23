// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "QuotaBar",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "QuotaBarCore", targets: ["QuotaBarCore"]),
        .library(name: "QuotaBarUI", targets: ["QuotaBarUI"]),
        .executable(name: "QuotaBar", targets: ["QuotaBar"]),
        .executable(name: "QuotaBarPreview", targets: ["QuotaBarPreview"]),
        .executable(name: "QuotaBarChecks", targets: ["QuotaBarChecks"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
    ],
    targets: [
        .target(name: "QuotaBarCore"),
        .target(
            name: "QuotaBarUI",
            dependencies: ["QuotaBarCore"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "QuotaBar",
            dependencies: ["QuotaBarUI", .product(name: "Sparkle", package: "Sparkle")]
        ),
        .executableTarget(
            name: "QuotaBarPreview",
            dependencies: ["QuotaBarUI"]
        ),
        .executableTarget(
            name: "QuotaBarChecks",
            dependencies: ["QuotaBarCore"]
        )
    ],
    swiftLanguageModes: [.v6]
)
