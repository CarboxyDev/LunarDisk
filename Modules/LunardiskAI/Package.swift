// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "LunardiskAI",
  platforms: [.macOS(.v14)],
  products: [
    .library(
      name: "LunardiskAI",
      targets: ["LunardiskAI"]
    )
  ],
  dependencies: [
    .package(path: "../CoreScan")
  ],
  targets: [
    .target(
      name: "LunardiskAI",
      dependencies: ["CoreScan"]
    ),
    .testTarget(
      name: "LunardiskAITests",
      dependencies: ["LunardiskAI", "CoreScan"]
    )
  ]
)

