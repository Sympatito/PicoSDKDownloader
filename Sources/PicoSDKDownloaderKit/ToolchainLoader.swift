import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Loads ARM toolchain metadata from supportedToolchains.ini.
/// Mimics pico-vscode behavior: try remote fetch, fall back to bundled offline cache.
public final class ToolchainLoader {
  private let http: HTTPClient
  private static let resourceName = "supportedToolchains"
  private static let resourceExtension = "ini"
  private static let resourceFilename = "\(resourceName).\(resourceExtension)"
  
  /// Remote URL for the supportedToolchains.ini (same as pico-vscode)
  /// This uses the GitHub Pages URL, not raw.githubusercontent.com
  /// NOTE: The version (0.18.0) should match CURRENT_DATA_VERSION in pico-vscode's sharedConstants.mts
  /// When pico-vscode updates this constant, update this URL accordingly.
  /// See: https://github.com/raspberrypi/pico-vscode/blob/main/src/utils/sharedConstants.mts
  private static let remoteURL = URL(string: "https://raspberrypi.github.io/pico-vscode/0.18.0/supportedToolchains.ini")!
  
  public init(http: HTTPClient) {
    self.http = http
  }
  
  /// Load toolchain metadata, trying remote first, then falling back to bundled resource.
  public func loadToolchainIndex() async throws -> ToolchainIndex {
    // Try remote fetch
    do {
      let (data, _) = try await http.get(Self.remoteURL)
      if let content = String(data: data, encoding: .utf8) {
        let parsed = INIParser.parse(content)
        return ToolchainIndex(sections: parsed, source: .remote)
      }
    } catch {
      print("Failed to fetch remote supportedToolchains.ini: \(error)")
    }
    
    // Fall back to bundled resource
    return try loadBundledToolchainIndex()
  }
  
  private func loadBundledToolchainIndex() throws -> ToolchainIndex {
    var attempted: [String] = []
    func tryLoad(from url: URL?) -> ToolchainIndex? {
      guard let url else { return nil }
      attempted.append(url.path)
      guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
      let parsed = INIParser.parse(content)
      return ToolchainIndex(sections: parsed, source: .bundledFallback)
    }
    
    #if SWIFT_PACKAGE
    if let index = tryLoad(from: Bundle.module.url(forResource: Self.resourceName, withExtension: Self.resourceExtension)) {
      return index
    }
    #endif
    
    if let index = tryLoad(from: Bundle.main.url(forResource: Self.resourceName, withExtension: Self.resourceExtension)) {
      return index
    }
    
    if let index = tryLoad(from: resourceURLNextToExecutable()) {
      return index
    }
    
    if let index = tryLoad(from: resourceURLInSourceTree()) {
      return index
    }

    let paths = attempted.joined(separator: ", ")
    throw PicoBootstrapError.notFound(
      "Failed to load bundled supportedToolchains.ini (checked: \(paths))"
    )
  }
  
  private func resourceURLNextToExecutable() -> URL? {
    let executablePath = ProcessInfo.processInfo.arguments[0]
    let executableURL = URL(fileURLWithPath: executablePath)
    let executableDir = executableURL.deletingLastPathComponent()
    let direct = executableDir.appendingPathComponent(Self.resourceFilename, isDirectory: false)
    if FileManager.default.fileExists(atPath: direct.path) {
      return direct
    }
    
    if let contents = try? FileManager.default.contentsOfDirectory(at: executableDir, includingPropertiesForKeys: [.isDirectoryKey]) {
      for url in contents where url.lastPathComponent.hasSuffix(".resources") {
        let iniURL = url.appendingPathComponent(Self.resourceFilename)
        if FileManager.default.fileExists(atPath: iniURL.path) {
          return iniURL
        }
      }
    }
    return nil
  }
  
  private func resourceURLInSourceTree() -> URL? {
    let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let candidate = sourceDir
      .appendingPathComponent("Resources", isDirectory: true)
      .appendingPathComponent(Self.resourceFilename, isDirectory: false)
    return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
  }
}

/// Represents the parsed toolchain index with metadata about where it came from.
public struct ToolchainIndex {
  public enum Source {
    case remote
    case bundledFallback
  }
  
  public let sections: [String: [String: String]]
  public let source: Source
  
  /// Get download URL for a specific version and platform key.
  /// Platform key format: darwin_arm64, darwin_x64, linux_arm64, linux_x64
  public func url(for version: String, platform: String) -> String? {
    return sections[version]?[platform]
  }
  
  public var isRemote: Bool {
    return source == .remote
  }
}

extension HostEnvironment {
  /// Map HostEnvironment to INI platform key.
  /// Format: darwin_arm64, darwin_x64, linux_arm64, linux_x64
  public var iniPlatformKey: String {
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
