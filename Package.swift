// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "QuotaBar",
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
    targets: [
        .target(name: "QuotaBarCore"),
        .target(
            name: "QuotaBarUI",
            dependencies: ["QuotaBarCore"]
        ),
        .executableTarget(
            name: "QuotaBar",
            dependencies: ["QuotaBarUI"]
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
