// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "pico-bootstrap",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "pico-bootstrap", targets: ["pico-bootstrap"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.4.0")
  ],
  targets: [
    .executableTarget(
      name: "pico-bootstrap",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ],
      path: "Sources",
      resources: [
        .copy("PicoSDKDownloader/Resources/supportedToolchains.ini")
      ]
    )
  ]
)