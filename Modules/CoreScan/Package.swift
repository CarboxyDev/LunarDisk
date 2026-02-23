// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "CoreScan",
  platforms: [.macOS(.v14)],
  products: [
    .library(
      name: "CoreScan",
      targets: ["CoreScan"]
    )
  ],
  targets: [
    .target(
      name: "CoreScan"
    ),
    .testTarget(
      name: "CoreScanTests",
      dependencies: ["CoreScan"]
    )
  ]
)

