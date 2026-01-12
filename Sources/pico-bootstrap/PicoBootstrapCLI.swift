import Foundation
import Dispatch
import ArgumentParser
import PicoSDKDownloaderKit

@discardableResult
private func runBlocking<T>(_ operation: @escaping () async throws -> T) throws -> T {
  #if os(macOS)
  // The other option is to add a restriction at the package level for macOS 13, but this then requires
  // all consumers to also restrict their packages to macOS 13, while this is host-only running code.
  // This is undesirable but provides better ergonomics.
  guard #available(macOS 13, *) else {
    throw PicoBootstrapError.unsupportedPlatform("macOS v13 is required.")
  }
  #endif

  let semaphore = DispatchSemaphore(value: 0)
  var result: Result<T, Error>?

  Task {
    do {
      let value = try await operation()
      result = .success(value)
    } catch {
      result = .failure(error)
    }
    semaphore.signal()
  }

  semaphore.wait()
  switch result {
  case .success(let value):
    return value
  case .failure(let error):
    throw error
  case .none:
    fatalError("runBlocking completed without producing a result.")
  }
}

@main
struct PicoBootstrap: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "pico-bootstrap",
    abstract: "Download/install Pico SDK + toolchain + tools into a pico-vscode compatible layout (~/.pico-sdk by default).",
    version: "0.1.0",
    subcommands: [Install.self, Resolve.self, List.self]
  )
}

extension PicoBootstrap {
  struct CommonOptions: ParsableArguments {
    @Option(name: .long, help: "Install root directory. Defaults to ~/.pico-sdk")
    var root: String?

    @Option(name: .long, help: "GitHub token (recommended to avoid rate limits).")
    var githubToken: String?

    var rootURL: URL {
      if let root, !root.isEmpty {
        return URL(fileURLWithPath: (root as NSString).expandingTildeInPath, isDirectory: true)
      }
      return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".pico-sdk", isDirectory: true)
    }
  }

  struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Install components for a specific SDK/toolchain/tool versions."
    )

    @OptionGroup var common: CommonOptions

    @Option(name: .long, help: "Pico SDK version tag, e.g. 2.2.0")
    var sdk: String

    @Option(name: .long, help: "ARM toolchain version, e.g. 14_2_Rel1 (underscore format).")
    var toolchain: String

    @Option(name: .long, help: "CMake version, e.g. 3.31.5")
    var cmake: String

    @Option(name: .long, help: "Ninja version, e.g. 1.12.1")
    var ninja: String

    @Option(name: .long, help: "Picotool version tag, e.g. 2.2.0-a4 (no leading v).")
    var picotool: String

    @Option(name: .long, help: "OpenOCD version, e.g. 0.12.0+dev")
    var openocd: String

    @Option(name: .long, help: "Install pico-sdk-tools for the SDK version (best effort).")
    var includeSdkTools: Bool = true

    func run() throws {
      try runBlocking {
        print("[PicoSDKDownloader] Starting installation...")
        let env = try HostEnvironment.detect()
        let http = HTTPClient(githubToken: common.githubToken)
        let gh = GitHubClient(http: http)
        let toolchainLoader = ToolchainLoader(http: http)

        print("[PicoSDKDownloader] Resolving versions and download URLs...")

        let resolver = VersionResolver(
          env: env,
          gitHub: gh,
          toolchainLoader: toolchainLoader,
          installRoot: common.rootURL,
          preferInstalled: true
        )
        let req = InstallRequest(
          sdkVersion: sdk,
          armToolchainVersion: toolchain,
          cmakeVersion: cmake,
          ninjaVersion: ninja,
          picotoolVersion: picotool,
          openocdVersion: openocd,
          includePicoSdkTools: includeSdkTools
        )

        print("[PicoSDKDownloader] Install request:")

        let plan = try await resolver.resolve(request: req)
        print(plan.prettyDescription)

        print("[PicoSDKDownloader] Starting installation...")

        let installer = Installer(env: env, http: http)
        try FileManager.default.createDirectory(at: common.rootURL, withIntermediateDirectories: true)

        let store = InstallManifestStore(root: common.rootURL)

        // Install in roughly the same order as pico-vscode switchSDK: SDK -> toolchain -> tools -> ninja/cmake/picotool
        try await installer.installPicoSDK(plan: plan, root: common.rootURL)
        try await store.record(plan: plan, component: .picoSDK)

        try await installer.installArmToolchain(plan: plan, root: common.rootURL)
        try await store.record(plan: plan, component: .armToolchain)

        if plan.picoSdkTools != nil {
          try await installer.installPicoSdkTools(plan: plan, root: common.rootURL)
          try await store.record(plan: plan, component: .picoSdkTools)
        }

        try await installer.installNinja(plan: plan, root: common.rootURL)
        try await store.record(plan: plan, component: .ninja)

        try await installer.installCMake(plan: plan, root: common.rootURL)
        try await store.record(plan: plan, component: .cmake)

        try await installer.installPicotool(plan: plan, root: common.rootURL)
        try await store.record(plan: plan, component: .picotool)

        try await installer.installOpenOCD(plan: plan, root: common.rootURL)
        try await store.record(plan: plan, component: .openocd)

        print("\n[PicoSDKDownloader] Done. Installed under: \(common.rootURL.path)")
      }
    }
  }

  struct Resolve: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Resolve an install plan (versions + URLs) without installing; useful for building your own UI."
    )

    @OptionGroup var common: CommonOptions

    @Option(name: .long, help: "Pico SDK version tag, e.g. 2.2.0")
    var sdk: String

    @Option(name: .long, help: "ARM toolchain version, e.g. 14_2_Rel1")
    var toolchain: String

    @Option(name: .long, help: "CMake version, e.g. 3.31.5")
    var cmake: String

    @Option(name: .long, help: "Ninja version, e.g. 1.12.1")
    var ninja: String

    @Option(name: .long, help: "Picotool version, e.g. 2.2.0-a4")
    var picotool: String

    @Option(name: .long, help: "OpenOCD version, e.g. 0.12.0+dev")
    var openocd: String

    @Option(name: .long, help: "Resolve pico-sdk-tools for this SDK version if available.")
    var includeSdkTools: Bool = true

    func run() throws {
      try runBlocking {
        let env = try HostEnvironment.detect()
        let http = HTTPClient(githubToken: common.githubToken)
        let gh = GitHubClient(http: http)
        let toolchainLoader = ToolchainLoader(http: http)
        let resolver = VersionResolver(env: env, gitHub: gh, toolchainLoader: toolchainLoader)

        let req = InstallRequest(
          sdkVersion: sdk,
          armToolchainVersion: toolchain,
          cmakeVersion: cmake,
          ninjaVersion: ninja,
          picotoolVersion: picotool,
          openocdVersion: openocd,
          includePicoSdkTools: includeSdkTools
        )

        let plan = try await resolver.resolve(request: req)
        print(plan.prettyDescription)

        // machine-readable JSON for reuse
        let data = try JSONEncoder.pretty.encode(plan)
        print("\n---\n\(String(data: data, encoding: .utf8)!)")
      }
    }
  }

  struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Discover what's available (best-effort) so you can offer user options."
    )

    @OptionGroup var common: CommonOptions

    enum Kind: String, ExpressibleByArgument {
      case sdkTags
      case picotoolReleases
      case picoSdkToolsReleases
      case armToolchainReleases
      case openocdReleases
    }

    @Option(name: .long, help: "What to list: sdkTags | picotoolReleases | picoSdkToolsReleases | armToolchainReleases | openocdReleases")
    var kind: Kind

    @Option(name: .long, help: "Limit results (default 30)")
    var limit: Int = 30

    func run() throws {
      try runBlocking {
        let http = HTTPClient(githubToken: common.githubToken)
        let gh = GitHubClient(http: http)

        switch kind {
        case .sdkTags:
          let tags = try await gh.listTags(owner: "raspberrypi", repo: "pico-sdk", limit: limit)
          for t in tags { print(t) }

        case .picotoolReleases:
          let rels = try await gh.listReleases(owner: "raspberrypi", repo: "picotool", limit: limit)
          for r in rels { print(r.tag_name) }

        case .picoSdkToolsReleases:
          let rels = try await gh.listReleases(owner: "raspberrypi", repo: "pico-sdk-tools", limit: limit)
          for r in rels { print(r.tag_name) }

        case .armToolchainReleases:
          // Load from supportedToolchains.ini instead of GitHub releases
          let toolchainLoader = ToolchainLoader(http: http)
          let index = try await toolchainLoader.loadToolchainIndex()
          
          // Sort versions in descending order with proper version comparison
          // Version format: XX_Y_RelZ or XX_Y-YYYY_MM
          let versions = Array(index.sections.keys).sorted { v1, v2 in
            // Extract numeric parts for comparison
            let v1Parts = v1.split(separator: "_").compactMap { Int($0) }
            let v2Parts = v2.split(separator: "_").compactMap { Int($0) }
            
            // Compare numeric parts up to the minimum count
            for i in 0..<min(v1Parts.count, v2Parts.count) {
              if v1Parts[i] != v2Parts[i] {
                return v1Parts[i] > v2Parts[i]
              }
            }
            
            // If all compared parts are equal, longer version (more parts) is considered newer
            if v1Parts.count != v2Parts.count {
              return v1Parts.count > v2Parts.count
            }
            
            // If numeric parts are identical, fall back to string comparison
            return v1 > v2
          }
          
          let limitedVersions = limit > 0 ? Array(versions.prefix(limit)) : versions
          for version in limitedVersions {
            print(version)
          }

        case .openocdReleases:
          // OpenOCD releases are distributed via pico-sdk-tools
          // Version mapping is maintained in VersionResolver.resolveOpenOCD()
          // Currently supported versions from pico-vscode:
          print("0.12.0+dev")
        }
      }
    }
  }
}
