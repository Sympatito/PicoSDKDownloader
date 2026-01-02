import Foundation

/// Responsible for "tell me exactly what versions+URLs will be used".
/// This is the reusable piece you can integrate into a UI to:
/// - resolve component versions
/// - discover what's available
final class VersionResolver {
  private let env: HostEnvironment
  private let gitHub: GitHubClient
  private let toolchainLoader: ToolchainLoader

  init(env: HostEnvironment, gitHub: GitHubClient, toolchainLoader: ToolchainLoader) {
    self.env = env
    self.gitHub = gitHub
    self.toolchainLoader = toolchainLoader
  }

  func resolve(request: InstallRequest) async throws -> InstallPlan {
    // Pico SDK: git tag (no archive URL needed)
    let picoSDK = ComponentPlan(
      id: .picoSDK,
      version: request.sdkVersion,
      installPathRelativeToRoot: "sdk/\(request.sdkVersion)",
      downloadURL: nil,
      archiveType: nil,
      notes: "Installed via git clone + checkout tag \(request.sdkVersion)"
    )

    // ARM toolchain: resolve from supportedToolchains.ini (remote + bundled fallback)
    let toolchain = try await resolveArmToolchain(version: request.armToolchainVersion)

    // pico-sdk-tools: try to resolve from raspberrypi/pico-sdk-tools; tag naming varies, so we search.
    let picoSdkTools = request.includePicoSdkTools
      ? try await resolvePicoSdkTools(forSDK: request.sdkVersion)
      : nil

    // CMake: use Kitware GitHub release assets; tag is commonly "v3.31.5"
    let cmake = try await resolveCMake(version: request.cmakeVersion)

    // Ninja: GitHub release assets (ninja-build/ninja)
    let ninja = try await resolveNinja(version: request.ninjaVersion)

    // picotool: raspberrypi/picotool release
    let picotool = try await resolvePicotool(version: request.picotoolVersion)

    return InstallPlan(
      env: env,
      request: request,
      picoSDK: picoSDK,
      armToolchain: toolchain,
      picoSdkTools: picoSdkTools,
      cmake: cmake,
      ninja: ninja,
      picotool: picotool
    )
  }

  // MARK: - Resolution helpers

  private func resolveArmToolchain(version: String) async throws -> ComponentPlan {
    // Load toolchain index from remote or bundled fallback
    let index = await toolchainLoader.loadToolchainIndex()
    let platformKey = env.iniPlatformKey
    
    guard let downloadURL = index.url(for: version, platform: platformKey) else {
      throw PicoBootstrapError.notFound("ARM toolchain version \(version) not found for platform \(platformKey) in supportedToolchains.ini")
    }
    
    // Determine archive type from URL
    let archiveType: String
    if downloadURL.hasSuffix(".tar.xz") {
      archiveType = "tar.xz"
    } else if downloadURL.hasSuffix(".tar.gz") {
      archiveType = "tar.gz"
    } else if downloadURL.hasSuffix(".tar.bz2") {
      archiveType = "tar.bz2"
    } else if downloadURL.hasSuffix(".pkg") {
      archiveType = "pkg"
    } else {
      archiveType = "unknown"
    }
    
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
        if env.arch == .x86_64 { return n.contains("linux") && n.contains("x86_64") }
        return n.contains("linux") && (n.contains("aarch64") || n.contains("arm64"))
      case .macos:
        // often "mac" or "osx"
        if env.arch == .x86_64 { return (n.contains("mac") || n.contains("osx")) && n.contains("x86_64") }
        return (n.contains("mac") || n.contains("osx")) && (n.contains("arm64") || n.contains("aarch64"))
      }
    }
    return assets.first(where: matches)
  }

  private func resolvePicotool(version: String) async throws -> ComponentPlan {
    // picotool tags are usually "v2.2.0-a4" (with v), but you pass "2.2.0-a4" (like pico-vscode default).
    let tag = version.hasPrefix("v") ? version : "v\(version)"
    let rel = try await gitHub.getReleaseByTag(owner: "raspberrypi", repo: "picotool", tag: tag)

    guard let asset = pickPicotoolAsset(release: rel) else {
      throw PicoBootstrapError.notFound("No matching picotool asset for \(env.os)/\(env.arch) in \(rel.tag_name)")
    }

    return ComponentPlan(
      id: .picotool,
      version: version,
      installPathRelativeToRoot: "picotool/\(version)",
      downloadURL: asset.browser_download_url,
      archiveType: asset.name.hasSuffix(".zip") ? "zip" : (asset.name.hasSuffix(".tar.gz") ? "tar.gz" : "unknown"),
      notes: "Resolved from raspberrypi/picotool \(rel.tag_name), asset \(asset.name)"
    )
  }

  private func pickPicotoolAsset(release: GitHubRelease) -> GitHubRelease.Asset? {
    let assets = release.assets
    func matches(_ a: GitHubRelease.Asset) -> Bool {
      let n = a.name.lowercased()
      if !(n.hasSuffix(".zip") || n.hasSuffix(".tar.gz")) { return false }

      switch env.os {
      case .linux:
        if env.arch == .x86_64 { return n.contains("linux") && n.contains("x86_64") }
        return n.contains("linux") && (n.contains("aarch64") || n.contains("arm64"))
      case .macos:
        if env.arch == .x86_64 { return (n.contains("mac") || n.contains("darwin") || n.contains("osx")) && n.contains("x86_64") }
        return (n.contains("mac") || n.contains("darwin") || n.contains("osx")) && (n.contains("arm64") || n.contains("aarch64"))
      }
    }
    return assets.first(where: matches)
  }
}