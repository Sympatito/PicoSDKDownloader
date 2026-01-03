// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "PicoSDKDownloader",
  products: [
    .library(name: "PicoSDKDownloaderKit", targets: ["PicoSDKDownloaderKit"]),
    .executable(name: "pico-bootstrap", targets: ["pico-bootstrap"]),
    .plugin(name: "PicoBootstrapPlugin", targets: ["PicoBootstrapPlugin"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.4.0")
  ],
  targets: [
    .target(
      name: "PicoSDKDownloaderKit",
      dependencies: [],
      path: "Sources/PicoSDKDownloaderKit",
      resources: [
        .copy("Resources/supportedToolchains.ini")
      ]
    ),
    .executableTarget(
      name: "pico-bootstrap",
      dependencies: [
        "PicoSDKDownloaderKit",
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ],
      path: "Sources/pico-bootstrap"
    ),
    .plugin(
      name: "PicoBootstrapPlugin",
      capability: .command(
        intent: .custom(
          verb: "pico-bootstrap",
          description: "Invoke pico-bootstrap from the SwiftPM command line."
        ),
        permissions: [
          .writeToPackageDirectory(reason: "Installs Pico SDK assets into the chosen root directory."),
          .allowNetworkConnections(scope: .all(), reason: "Allows network connections for downloading SDK assets.")
        ]
      ),
      dependencies: [
        .target(name: "pico-bootstrap")
      ],
      path: "Sources/PicoBootstrapPlugin"
    )
  ]
)
