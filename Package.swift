// swift-tools-version: 5.10

import PackageDescription

let package = Package(
  name: "Dex",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "Dex", targets: ["Dex"]),
    .library(name: "DexCore", targets: ["DexCore"]),
  ],
  targets: [
    .target(name: "DexCore"),
    .executableTarget(
      name: "Dex",
      dependencies: ["DexCore"]
    ),
    .testTarget(
      name: "DexCoreTests",
      dependencies: ["DexCore"]
    ),
    .testTarget(
      name: "DexTests",
      dependencies: ["Dex"]
    ),
  ],
  swiftLanguageVersions: [.v5]
)
