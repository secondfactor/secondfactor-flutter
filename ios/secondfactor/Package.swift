// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "secondfactor",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "secondfactor", targets: ["secondfactor"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "secondfactor",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
