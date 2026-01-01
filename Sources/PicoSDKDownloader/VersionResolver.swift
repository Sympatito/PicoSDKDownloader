import Foundation

/// Responsible for "tell me exactly what versions+URLs will be used".
/// This is the reusable piece you can integrate into a UI to:
/// - resolve component versions
/// - discover what's available
final class VersionResolver {
  private let env: HostEnvironment
  private let gitHub: GitHubClient

  init(env: HostEnvironment, gitHub: GitHubClient) {
    self.env = env
    self.gitHub = gitHub
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

    // ARM toolchain: best-effort asset selection from ARM-software/toolchain-gnu-bare-metal releases.
    // We accept request.armToolchainVersion in underscore format, but ARM tags use dotted form (commonly).
    let toolchainTagCandidates = toolchainTagCandidates(from: request.armToolchainVersion)
    let toolchain = try await resolveArmToolchain(version: request.armToolchainVersion, tagCandidates: toolchainTagCandidates)

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

  private func toolchainTagCandidates(from underscore: String) -> [String] {
    // 14_2_Rel1 -> 14.2.Rel1 (common display) + some typical tag forms
    let dotted = underscore.replacingOccurrences(of: "_", with: ".")
    // Many ARM repos use tags like "14.2.rel1" or "14.2.Rel1" (varies)
    let lowerRel = dotted.replacingOccurrences(of: "Rel", with: "rel")
    return [
      dotted,
      lowerRel,
      "v\(dotted)",
      "v\(lowerRel)"
    ]
  }

  private func resolveArmToolchain(version: String, tagCandidates: [String]) async throws -> ComponentPlan {
    // Try candidates until a tag works.
    var lastErr: Error?
    for tag in tagCandidates {
      do {
        let rel = try await gitHub.getReleaseByTag(owner: "ARM-software", repo: "toolchain-gnu-bare-metal", tag: tag)
        if let asset = pickArmToolchainAsset(release: rel) {
          return ComponentPlan(
            id: .armToolchain,
            version: version,
            installPathRelativeToRoot: "toolchain/\(version)",
            downloadURL: asset.browser_download_url,
            archiveType: asset.name.hasSuffix(".tar.xz") ? "tar.xz" : (asset.name.hasSuffix(".tar.gz") ? "tar.gz" : "unknown"),
            notes: "Resolved from tag \(rel.tag_name), asset \(asset.name)"
          )
        }
        throw PicoBootstrapError.notFound("No matching toolchain asset in release \(rel.tag_name)")
      } catch {
        lastErr = error
      }
    }
    throw lastErr ?? PicoBootstrapError.notFound("Could not resolve ARM toolchain release for \(version)")
  }

  private func pickArmToolchainAsset(release: GitHubRelease) -> GitHubRelease.Asset? {
    // ARM toolchain assets often include strings like:
    // - x86_64-linux / aarch64-linux / darwin-x86_64 / darwin-arm64
    // We pick a tar archive that matches OS/arch.
    let assets = release.assets

    func matches(_ a: GitHubRelease.Asset) -> Bool {
      let n = a.name.lowercased()
      guard n.hasSuffix(".tar.xz") || n.hasSuffix(".tar.gz") else { return false }

      switch env.os {
      case .linux:
        if env.arch == .x86_64 { return n.contains("x86_64") && n.contains("linux") }
        return n.contains("aarch64") && n.contains("linux")
      case .macos:
        // Some toolchain releases might not ship macOS; if not found, fail.
        if env.arch == .x86_64 { return n.contains("darwin") && n.contains("x86_64") }
        return n.contains("darwin") && (n.contains("arm64") || n.contains("aarch64"))
      }
    }

    return assets.first(where: matches)
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