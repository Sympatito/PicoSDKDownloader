import Foundation
import ArgumentParser

@main
struct PicoBootstrap: AsyncParsableCommand {
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

  struct Install: AsyncParsableCommand {
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

    @Option(name: .long, help: "Install pico-sdk-tools for the SDK version (best effort).")
    var includeSdkTools: Bool = true

    func run() async throws {
      let env = try HostEnvironment.detect()
      let http = HTTPClient(githubToken: common.githubToken)
      let gh = GitHubClient(http: http)

      let resolver = VersionResolver(env: env, gitHub: gh)
      let req = InstallRequest(
        sdkVersion: sdk,
        armToolchainVersion: toolchain,
        cmakeVersion: cmake,
        ninjaVersion: ninja,
        picotoolVersion: picotool,
        includePicoSdkTools: includeSdkTools
      )

      let plan = try await resolver.resolve(request: req)
      print(plan.prettyDescription)

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

      print("\nDone. Installed under: \(common.rootURL.path)")
    }
  }

  struct Resolve: AsyncParsableCommand {
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

    @Option(name: .long, help: "Resolve pico-sdk-tools for this SDK version if available.")
    var includeSdkTools: Bool = true

    func run() async throws {
      let env = try HostEnvironment.detect()
      let http = HTTPClient(githubToken: common.githubToken)
      let gh = GitHubClient(http: http)
      let resolver = VersionResolver(env: env, gitHub: gh)

      let req = InstallRequest(
        sdkVersion: sdk,
        armToolchainVersion: toolchain,
        cmakeVersion: cmake,
        ninjaVersion: ninja,
        picotoolVersion: picotool,
        includePicoSdkTools: includeSdkTools
      )

      let plan = try await resolver.resolve(request: req)
      print(plan.prettyDescription)

      // machine-readable JSON for reuse
      let data = try JSONEncoder.pretty.encode(plan)
      print("\n---\n\(String(data: data, encoding: .utf8)!)")
    }
  }

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Discover what's available (best-effort) so you can offer user options."
    )

    @OptionGroup var common: CommonOptions

    enum Kind: String, ExpressibleByArgument {
      case sdkTags
      case picotoolReleases
      case picoSdkToolsReleases
      case armToolchainReleases
    }

    @Option(name: .long, help: "What to list: sdkTags | picotoolReleases | picoSdkToolsReleases | armToolchainReleases")
    var kind: Kind

    @Option(name: .long, help: "Limit results (default 30)")
    var limit: Int = 30

    func run() async throws {
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
        let rels = try await gh.listReleases(owner: "ARM-software", repo: "toolchain-gnu-bare-metal", limit: limit)
        for r in rels { print(r.tag_name) }
      }
    }
  }
}