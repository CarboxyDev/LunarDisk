// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "Visualization",
  platforms: [.macOS(.v14)],
  products: [
    .library(
      name: "Visualization",
      targets: ["Visualization"]
    )
  ],
  dependencies: [
    .package(path: "../CoreScan")
  ],
  targets: [
    .target(
      name: "Visualization",
      dependencies: ["CoreScan"]
    ),
    .testTarget(
      name: "VisualizationTests",
      dependencies: ["Visualization", "CoreScan"]
    )
  ]
)

