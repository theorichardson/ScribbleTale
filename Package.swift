// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ScribbleTaleDeps",
    platforms: [.iOS(.v18)],
    products: [],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "2.31.3"),
        .package(url: "https://github.com/apple/ml-stable-diffusion", from: "1.1.1"),
    ],
    targets: []
)
