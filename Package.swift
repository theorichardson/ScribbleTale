// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ScribbleTaleDeps",
    platforms: [.iOS(.v18)],
    products: [],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "0.2.0"),
    ],
    targets: []
)
