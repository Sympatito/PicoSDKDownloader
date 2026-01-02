import Foundation

/// Lightweight record of what got installed and from which resolved plan.
/// This is deliberately simple but gives you parity with "what versions are installed" tracking.
public final class InstallManifestStore {
  struct Manifest: Codable {
    var installedAtISO8601: String
    var env: HostEnvironment
    var components: [ComponentId: ComponentEntry]
  }

  struct ComponentEntry: Codable {
    var version: String
    var relativePath: String
    var sourceURL: String?
  }

  private let root: URL
  private var manifestURL: URL { root.appendingPathComponent("pico-bootstrap-manifest.json") }

  public init(root: URL) {
    self.root = root
  }

  public func record(plan: InstallPlan, component: ComponentId) async throws {
    var m = try loadOrCreate(env: plan.env)
    let now = ISO8601DateFormatter().string(from: Date())
    m.installedAtISO8601 = now

    func entry(for c: ComponentPlan) -> ComponentEntry {
      ComponentEntry(version: c.version, relativePath: c.installPathRelativeToRoot, sourceURL: c.downloadURL)
    }

    switch component {
    case .picoSDK:
      m.components[.picoSDK] = entry(for: plan.picoSDK)
    case .armToolchain:
      m.components[.armToolchain] = entry(for: plan.armToolchain)
    case .picoSdkTools:
      if let p = plan.picoSdkTools { m.components[.picoSdkTools] = entry(for: p) }
    case .cmake:
      m.components[.cmake] = entry(for: plan.cmake)
    case .ninja:
      m.components[.ninja] = entry(for: plan.ninja)
    case .picotool:
      m.components[.picotool] = entry(for: plan.picotool)
    }

    let data = try JSONEncoder.pretty.encode(m)
    try data.write(to: manifestURL, options: [.atomic])
  }

  private func loadOrCreate(env: HostEnvironment) throws -> Manifest {
    if FileManager.default.fileExists(atPath: manifestURL.path) {
      let data = try Data(contentsOf: manifestURL)
      return try JSONDecoder().decode(Manifest.self, from: data)
    }
    return Manifest(
      installedAtISO8601: ISO8601DateFormatter().string(from: Date()),
      env: env,
      components: [:]
    )
  }
}
