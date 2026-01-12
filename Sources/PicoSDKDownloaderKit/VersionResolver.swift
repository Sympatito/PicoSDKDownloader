import Foundation

/// Responsible for "tell me exactly what versions+URLs will be used".
/// This is the reusable piece you can integrate into a UI to:
/// - resolve component versions
/// - discover what's available
public final class VersionResolver {
  private let env: HostEnvironment
  private let gitHub: GitHubClient
  private let toolchainLoader: ToolchainLoader
  private let installRoot: URL?
  private let preferInstalled: Bool

  public init(
    env: HostEnvironment,
    gitHub: GitHubClient,
    toolchainLoader: ToolchainLoader,
    installRoot: URL? = nil,
    preferInstalled: Bool = false
  ) {
    self.env = env
    self.gitHub = gitHub
    self.toolchainLoader = toolchainLoader
    self.installRoot = installRoot
    self.preferInstalled = preferInstalled
  }

  public func resolve(request: InstallRequest) async throws -> InstallPlan {
    // Pico SDK: git tag (no archive URL needed)
    let picoSDK = localPlanIfInstalled(
      id: .picoSDK,
      version: request.sdkVersion,
      installPathRelativeToRoot: "sdk/\(request.sdkVersion)"
    ) ?? ComponentPlan(
      id: .picoSDK,
      version: request.sdkVersion,
      installPathRelativeToRoot: "sdk/\(request.sdkVersion)",
      downloadURL: nil,
      archiveType: nil,
      notes: "Installed via git clone + checkout tag \(request.sdkVersion)"
    )

    // ARM toolchain: resolve from supportedToolchains.ini (remote + bundled fallback)
    let toolchain: ComponentPlan
    if let local = localPlanIfInstalled(
      id: .armToolchain,
      version: request.armToolchainVersion,
      installPathRelativeToRoot: "toolchain/\(request.armToolchainVersion)"
    ) {
      toolchain = local
    } else {
      toolchain = try await resolveArmToolchain(version: request.armToolchainVersion)
    }

    // pico-sdk-tools: try to resolve from raspberrypi/pico-sdk-tools; tag naming varies, so we search.
    let picoSdkTools: ComponentPlan?
    if request.includePicoSdkTools {
      if let local = localPlanIfInstalled(
        id: .picoSdkTools,
        version: request.sdkVersion,
        installPathRelativeToRoot: "tools/\(request.sdkVersion)"
      ) {
        picoSdkTools = local
      } else {
        picoSdkTools = try await resolvePicoSdkTools(forSDK: request.sdkVersion)
      }
    } else {
      picoSdkTools = nil
    }

    // CMake: use Kitware GitHub release assets; tag is commonly "v3.31.5"
    let cmakeTag = request.cmakeVersion.hasPrefix("v") ? request.cmakeVersion : "v\(request.cmakeVersion)"
    let cmake: ComponentPlan
    if let local = localPlanIfInstalled(
      id: .cmake,
      version: request.cmakeVersion,
      installPathRelativeToRoot: "cmake/\(cmakeTag)"
    ) {
      cmake = local
    } else {
      cmake = try await resolveCMake(version: request.cmakeVersion)
    }

    // Ninja: GitHub release assets (ninja-build/ninja)
    let ninjaTag = request.ninjaVersion.hasPrefix("v") ? request.ninjaVersion : "v\(request.ninjaVersion)"
    let ninja: ComponentPlan
    if let local = localPlanIfInstalled(
      id: .ninja,
      version: request.ninjaVersion,
      installPathRelativeToRoot: "ninja/\(ninjaTag)"
    ) {
      ninja = local
    } else {
      ninja = try await resolveNinja(version: request.ninjaVersion)
    }

    // picotool: raspberrypi/picotool release
    let picotool: ComponentPlan
    if let local = localPlanIfInstalled(
      id: .picotool,
      version: request.picotoolVersion,
      installPathRelativeToRoot: "picotool/\(request.picotoolVersion)"
    ) {
      picotool = local
    } else {
      picotool = try await resolvePicotool(version: request.picotoolVersion)
    }

    // openocd: raspberrypi/pico-sdk-tools release
    let openocd: ComponentPlan
    if let local = localPlanIfInstalled(
      id: .openocd,
      version: request.openocdVersion,
      installPathRelativeToRoot: "openocd/\(request.openocdVersion)"
    ) {
      openocd = local
    } else {
      openocd = try await resolveOpenOCD(version: request.openocdVersion)
    }

    return InstallPlan(
      env: env,
      request: request,
      picoSDK: picoSDK,
      armToolchain: toolchain,
      picoSdkTools: picoSdkTools,
      cmake: cmake,
      ninja: ninja,
      picotool: picotool,
      openocd: openocd
    )
  }

  // MARK: - Resolution helpers
  private func localPlanIfInstalled(
    id: ComponentId,
    version: String,
    installPathRelativeToRoot: String
  ) -> ComponentPlan? {
    guard preferInstalled, let installRoot else { return nil }
    let dest = installRoot.appendingPathComponent(installPathRelativeToRoot, isDirectory: true)
    guard FileManager.default.fileExists(atPath: dest.path) else { return nil }

    return ComponentPlan(
      id: id,
      version: version,
      installPathRelativeToRoot: installPathRelativeToRoot,
      downloadURL: nil,
      archiveType: nil,
      notes: "Found existing install at \(dest.path); skipping remote resolution"
    )
  }

  private func detectArchiveType(from url: String) -> String {
    if url.hasSuffix(".tar.xz") {
      return "tar.xz"
    } else if url.hasSuffix(".tar.gz") {
      return "tar.gz"
    } else if url.hasSuffix(".tar.bz2") {
      return "tar.bz2"
    } else if url.hasSuffix(".pkg") {
      return "pkg"
    } else if url.hasSuffix(".zip") {
      return "zip"
    } else {
      return "unknown"
    }
  }

  private func resolveArmToolchain(version: String) async throws -> ComponentPlan {
    // Load toolchain index from remote or bundled fallback
    let index = try await toolchainLoader.loadToolchainIndex()
    let platformKey = env.iniPlatformKey
    
    guard let downloadURL = index.url(for: version, platform: platformKey) else {
      throw PicoBootstrapError.notFound("ARM toolchain version \(version) not found for platform \(platformKey) in supportedToolchains.ini")
    }
    
    let archiveType = detectArchiveType(from: downloadURL)
    let source = index.isRemote ? "remote supportedToolchains.ini" : "bundled supportedToolchains.ini (offline cache)"
    
    return ComponentPlan(
      id: .armToolchain,
      version: version,
      installPathRelativeToRoot: "toolchain/\(version)",
      downloadURL: downloadURL,
      archiveType: archiveType,
      notes: "Resolved from \(source), platform \(platformKey)"
    )
  }

  private func resolvePicoSdkTools(forSDK sdkVersion: String) async throws -> ComponentPlan? {
    // pico-vscode uses a mapping (TOOLS_RELEASES) for some SDK versions.
    // Here we do "best-effort" by looking for a release whose tag includes the sdk version.
    let rels = try await gitHub.listReleases(owner: "raspberrypi", repo: "pico-sdk-tools", limit: 50)
      .filter { !$0.draft }

    // Prefer exact match patterns: "v2.2.0-0" or "2.2.0-0" etc.
    let candidates = rels.sorted { $0.tag_name > $1.tag_name }
    let chosen = candidates.first { $0.tag_name.contains(sdkVersion) } ?? candidates.first
    guard let chosen else { return nil }

    guard let asset = pickPicoSdkToolsAsset(release: chosen, sdkVersion: sdkVersion) else {
      // If no matching asset, just say nil (optional component).
      return nil
    }

    return ComponentPlan(
      id: .picoSdkTools,
      version: sdkVersion,
      installPathRelativeToRoot: "tools/\(sdkVersion)",
      downloadURL: asset.browser_download_url,
      archiveType: asset.name.hasSuffix(".zip") ? "zip" : (asset.name.hasSuffix(".tar.gz") ? "tar.gz" : "unknown"),
      notes: "Resolved from pico-sdk-tools tag \(chosen.tag_name), asset \(asset.name)"
    )
  }

  private func pickPicoSdkToolsAsset(release: GitHubRelease, sdkVersion: String) -> GitHubRelease.Asset? {
    let assets = release.assets
    func matches(_ a: GitHubRelease.Asset) -> Bool {
      let n = a.name.lowercased()
      // pico-vscode uses tar.gz on linux, zip on others. We'll allow either.
      if !(n.hasSuffix(".zip") || n.hasSuffix(".tar.gz")) { return false }

      // Expect "pico-sdk-tools-<sdkVersion>-<platform>.<ext>".
      // We'll match sdkVersion and OS/arch hints.
      guard n.contains(sdkVersion.lowercased()) else { return false }

      switch env.os {
      case .linux:
        if env.arch == .x86_64 { return n.contains("linux") && n.contains("x86_64") }
        return n.contains("linux") && (n.contains("aarch64") || n.contains("arm64"))
      case .macos:
        // Often "macos" is used; allow "darwin" too.
        if env.arch == .x86_64 { return (n.contains("macos") || n.contains("darwin")) && n.contains("x86_64") }
        return (n.contains("macos") || n.contains("darwin")) && (n.contains("arm64") || n.contains("aarch64"))
      }
    }
    return assets.first(where: matches)
  }

  private func resolveCMake(version: String) async throws -> ComponentPlan {
    let tag = version.hasPrefix("v") ? version : "v\(version)"
    let rel = try await gitHub.getReleaseByTag(owner: "Kitware", repo: "CMake", tag: tag)

    guard let asset = pickCMakeAsset(release: rel, version: version) else {
      throw PicoBootstrapError.notFound("No matching CMake asset for \(env.os)/\(env.arch) in \(rel.tag_name)")
    }

    return ComponentPlan(
      id: .cmake,
      version: version,
      installPathRelativeToRoot: "cmake/\(tag)",
      downloadURL: asset.browser_download_url,
      archiveType: asset.name.hasSuffix(".zip") ? "zip" : (asset.name.hasSuffix(".tar.gz") ? "tar.gz" : "unknown"),
      notes: "Resolved from Kitware/CMake \(rel.tag_name), asset \(asset.name)"
    )
  }

  private func pickCMakeAsset(release: GitHubRelease, version: String) -> GitHubRelease.Asset? {
    let assets = release.assets
    func matches(_ a: GitHubRelease.Asset) -> Bool {
      let n = a.name.lowercased()
      guard n.contains("cmake-\(version)") else { return false }

      switch env.os {
      case .linux:
        // Prefer tar.gz.
        if !(n.hasSuffix(".tar.gz") || n.hasSuffix(".tar.xz")) { return false }
        if env.arch == .x86_64 { return n.contains("linux") && (n.contains("x86_64") || n.contains("x64")) }
        return n.contains("linux") && (n.contains("aarch64") || n.contains("arm64"))
      case .macos:
        // pico-vscode uses universal app bundle archive (tar.gz) for mac.
        if !n.hasSuffix(".tar.gz") { return false }
        return n.contains("macos") && (n.contains("universal") || n.contains("x86_64") || n.contains("arm64"))
      }
    }
    return assets.first(where: matches)
  }

  private func resolveNinja(version: String) async throws -> ComponentPlan {
    let tag = version.hasPrefix("v") ? version : "v\(version)"
    let rel = try await gitHub.getReleaseByTag(owner: "ninja-build", repo: "ninja", tag: tag)

    guard let asset = pickNinjaAsset(release: rel) else {
      throw PicoBootstrapError.notFound("No matching Ninja asset for \(env.os)/\(env.arch) in \(rel.tag_name)")
    }

    return ComponentPlan(
      id: .ninja,
      version: version,
      installPathRelativeToRoot: "ninja/\(tag)",
      downloadURL: asset.browser_download_url,
      archiveType: asset.name.hasSuffix(".zip") ? "zip" : "unknown",
      notes: "Resolved from ninja-build/ninja \(rel.tag_name), asset \(asset.name)"
    )
  }

  private func pickNinjaAsset(release: GitHubRelease) -> GitHubRelease.Asset? {
    let assets = release.assets
    func matches(_ a: GitHubRelease.Asset) -> Bool {
      let n = a.name.lowercased()
      guard n.hasSuffix(".zip") else { return false }

      switch env.os {
      case .linux:
        // Ninja doesn't differentiate by architecture - "ninja-linux.zip" works for both x86_64 and aarch64
        // For arm64, there's a specific "ninja-linux-aarch64.zip" starting from some versions
        if env.arch == .aarch64 {
          return n == "ninja-linux-aarch64.zip" || (n == "ninja-linux.zip" && !assets.contains(where: { $0.name.lowercased() == "ninja-linux-aarch64.zip" }))
        }
        return n == "ninja-linux.zip"
      case .macos:
        // macOS uses universal binary "ninja-mac.zip"
        return n == "ninja-mac.zip"
      }
    }
    return assets.first(where: matches)
  }

  private func resolvePicotool(version: String) async throws -> ComponentPlan {
    // picotool binaries are in pico-sdk-tools, not picotool repo
    // Version mapping from pico-vscode: 2.2.0-a4 -> v2.2.0-3
    let picotoolReleaseMapping: [String: String] = [
      "2.0.0": "v2.0.0-5",
      "2.1.0": "v2.1.0-0",
      "2.1.1": "v2.1.1-1",
      "2.2.0": "v2.2.0-0",
      "2.2.0-a4": "v2.2.0-3"
    ]
    
    let releaseVersion = picotoolReleaseMapping[version] ?? "v\(version)-0"
    let rel = try await gitHub.getReleaseByTag(owner: "raspberrypi", repo: "pico-sdk-tools", tag: releaseVersion)

    guard let asset = pickPicotoolAsset(release: rel, version: version) else {
      throw PicoBootstrapError.notFound("No matching picotool asset for \(env.os)/\(env.arch) in pico-sdk-tools \(rel.tag_name)")
    }

    return ComponentPlan(
      id: .picotool,
      version: version,
      installPathRelativeToRoot: "picotool/\(version)",
      downloadURL: asset.browser_download_url,
      archiveType: asset.name.hasSuffix(".zip") ? "zip" : (asset.name.hasSuffix(".tar.gz") ? "tar.gz" : "unknown"),
      notes: "Resolved from raspberrypi/pico-sdk-tools \(rel.tag_name), asset \(asset.name)"
    )
  }

  private func pickPicotoolAsset(release: GitHubRelease, version: String) -> GitHubRelease.Asset? {
    let assets = release.assets
    func matches(_ a: GitHubRelease.Asset) -> Bool {
      let n = a.name.lowercased()
      if !(n.hasSuffix(".zip") || n.hasSuffix(".tar.gz")) { return false }
      
      // picotool assets are named: picotool-{version}-{arch}-{platform}.{ext}
      // e.g., picotool-2.2.0-a4-x86_64-lin.tar.gz, picotool-2.2.0-a4-mac.zip
      guard n.hasPrefix("picotool-\(version.lowercased())") else { return false }

      switch env.os {
      case .linux:
        // Linux: picotool-X.X.X-{arch}-lin.tar.gz
        if env.arch == .x86_64 { return n.contains("x86_64") && n.contains("lin") }
        if env.arch == .aarch64 { return n.contains("aarch64") && n.contains("lin") }
        return false
      case .macos:
        // macOS: picotool-X.X.X-mac.zip (universal binary)
        return n.contains("mac")
      }
    }
    return assets.first(where: matches)
  }

  private func resolveOpenOCD(version: String) async throws -> ComponentPlan {
    // OpenOCD binaries are in pico-sdk-tools, similar to picotool
    // Version mapping from pico-vscode: 0.12.0+dev -> v2.2.0-3
    // To add new versions: check pico-vscode's OPENOCD_RELEASES constant in src/utils/download.mts
    // and add the mapping here (version: pico-sdk-tools release tag)
    let openocdReleaseMapping: [String: String] = [
      "0.12.0+dev": "v2.2.0-3"
    ]
    
    let releaseVersion = openocdReleaseMapping[version] ?? "v\(version)-0"
    let rel = try await gitHub.getReleaseByTag(owner: "raspberrypi", repo: "pico-sdk-tools", tag: releaseVersion)

    guard let asset = pickOpenOCDAsset(release: rel, version: version) else {
      throw PicoBootstrapError.notFound("No matching openocd asset for \(env.os)/\(env.arch) in pico-sdk-tools \(rel.tag_name)")
    }

    return ComponentPlan(
      id: .openocd,
      version: version,
      installPathRelativeToRoot: "openocd/\(version)",
      downloadURL: asset.browser_download_url,
      archiveType: asset.name.hasSuffix(".zip") ? "zip" : (asset.name.hasSuffix(".tar.gz") ? "tar.gz" : "unknown"),
      notes: "Resolved from raspberrypi/pico-sdk-tools \(rel.tag_name), asset \(asset.name)"
    )
  }

  private func pickOpenOCDAsset(release: GitHubRelease, version: String) -> GitHubRelease.Asset? {
    let assets = release.assets
    func matches(_ a: GitHubRelease.Asset) -> Bool {
      let n = a.name.lowercased()
      if !(n.hasSuffix(".zip") || n.hasSuffix(".tar.gz")) { return false }
      
      // openocd assets are named: openocd-{version}-{arch}-{platform}.{ext}
      // e.g., openocd-0.12.0+dev-x86_64-lin.tar.gz, openocd-0.12.0+dev-mac.zip
      guard n.hasPrefix("openocd-\(version.lowercased())") else { return false }

      switch env.os {
      case .linux:
        // Linux: openocd-X.X.X-{arch}-lin.tar.gz
        if env.arch == .x86_64 { return n.contains("x86_64") && n.contains("lin") }
        if env.arch == .aarch64 { return n.contains("aarch64") && n.contains("lin") }
        return false
      case .macos:
        // macOS: openocd-X.X.X-mac.zip (universal binary)
        return n.contains("mac")
      }
    }
    return assets.first(where: matches)
  }
}
