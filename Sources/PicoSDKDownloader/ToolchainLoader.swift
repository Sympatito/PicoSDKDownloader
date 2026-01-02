import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Loads ARM toolchain metadata from supportedToolchains.ini.
/// Mimics pico-vscode behavior: try remote fetch, fall back to bundled offline cache.
final class ToolchainLoader {
  private let http: HTTPClient
  
  /// Remote URL for the supportedToolchains.ini (same as pico-vscode)
  private static let remoteURL = URL(string: "https://raw.githubusercontent.com/raspberrypi/pico-vscode/main/data/supportedToolchains.ini")!
  
  init(http: HTTPClient) {
    self.http = http
  }
  
  /// Load toolchain metadata, trying remote first, then falling back to bundled resource.
  func loadToolchainIndex() async -> ToolchainIndex {
    // Try remote fetch
    do {
      let (data, _) = try await http.get(Self.remoteURL)
      if let content = String(data: data, encoding: .utf8) {
        let parsed = INIParser.parse(content)
        return ToolchainIndex(sections: parsed, source: .remote)
      }
    } catch {
      // Remote fetch failed, will fall back to bundled
    }
    
    // Fall back to bundled resource
    return loadBundledToolchainIndex()
  }
  
  private func loadBundledToolchainIndex() -> ToolchainIndex {
    // In SPM, resources are placed alongside the executable with a special name pattern
    // For executable targets, we need to look for the .resources bundle
    
    // Get the path to the executable
    let executablePath = ProcessInfo.processInfo.arguments[0]
    let executableURL = URL(fileURLWithPath: executablePath)
    let executableDir = executableURL.deletingLastPathComponent()
    
    // Try to find the resources bundle by searching for *.resources directories
    // Pattern: <target>_<module>.resources/ (e.g., pico-bootstrap_pico-bootstrap.resources)
    if let enumerator = FileManager.default.enumerator(at: executableDir, includingPropertiesForKeys: [.isDirectoryKey]) {
      for case let url as URL in enumerator {
        if url.lastPathComponent.hasSuffix(".resources") {
          let iniURL = url.appendingPathComponent("supportedToolchains.ini")
          if let content = try? String(contentsOf: iniURL, encoding: .utf8) {
            let parsed = INIParser.parse(content)
            return ToolchainIndex(sections: parsed, source: .bundledFallback)
          }
        }
      }
    }
    
    // If resource not found, return empty index
    return ToolchainIndex(sections: [:], source: .bundledFallback)
  }
}

/// Represents the parsed toolchain index with metadata about where it came from.
struct ToolchainIndex {
  enum Source {
    case remote
    case bundledFallback
  }
  
  let sections: [String: [String: String]]
  let source: Source
  
  /// Get download URL for a specific version and platform key.
  /// Platform key format: darwin_arm64, darwin_x64, linux_arm64, linux_x64
  func url(for version: String, platform: String) -> String? {
    return sections[version]?[platform]
  }
  
  var isRemote: Bool {
    return source == .remote
  }
}

extension HostEnvironment {
  /// Map HostEnvironment to INI platform key.
  /// Format: darwin_arm64, darwin_x64, linux_arm64, linux_x64
  var iniPlatformKey: String {
    let osPrefix: String
    switch os {
    case .macos: osPrefix = "darwin"
    case .linux: osPrefix = "linux"
    }
    
    let archSuffix: String
    switch arch {
    case .x86_64: archSuffix = "x64"
    case .aarch64: archSuffix = "arm64"
    }
    
    return "\(osPrefix)_\(archSuffix)"
  }
}
