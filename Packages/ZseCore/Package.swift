// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZseCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ZseCore",
            targets: ["ZseCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19")
    ],
    targets: [
        .target(
            name: "ZseCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "Sources/ZseCore"
        ),
        .testTarget(
            name: "ZseCoreTests",
            dependencies: ["ZseCore"],
            path: "Tests/ZseCoreTests"
        )
    ]
)
