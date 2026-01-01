import Foundation

enum ComponentId: String, Codable {
  case picoSDK = "pico-sdk"
  case armToolchain = "arm-toolchain"
  case picoSdkTools = "pico-sdk-tools"
  case cmake = "cmake"
  case ninja = "ninja"
  case picotool = "picotool"
}

struct InstallRequest: Codable {
  var sdkVersion: String
  var armToolchainVersion: String  // e.g. 14_2_Rel1
  var cmakeVersion: String         // e.g. 3.31.5
  var ninjaVersion: String         // e.g. 1.12.1
  var picotoolVersion: String      // e.g. 2.2.0-a4
  var includePicoSdkTools: Bool
}

struct ComponentPlan: Codable {
  let id: ComponentId
  let version: String
  let installPathRelativeToRoot: String
  let downloadURL: String?     // nil for git-based installs
  let archiveType: String?     // "zip" | "tar.gz" | "tar.xz" | nil
  let notes: String?
}

struct InstallPlan: Codable {
  let env: HostEnvironment
  let request: InstallRequest
  let picoSDK: ComponentPlan
  let armToolchain: ComponentPlan
  let picoSdkTools: ComponentPlan?
  let cmake: ComponentPlan
  let ninja: ComponentPlan
  let picotool: ComponentPlan

  var prettyDescription: String {
    var lines: [String] = []
    lines.append("Resolved plan:")
    lines.append("- host: \(env.os.rawValue) / \(env.arch.rawValue)")
    for c in componentsInOrder {
      lines.append("  - \(c.id.rawValue) \(c.version)")
      lines.append("    path: \(c.installPathRelativeToRoot)")
      if let u = c.downloadURL { lines.append("    url:  \(u)") }
      if let a = c.archiveType { lines.append("    archive: \(a)") }
      if let n = c.notes { lines.append("    note: \(n)") }
    }
    return lines.joined(separator: "\n")
  }

  var componentsInOrder: [ComponentPlan] {
    var all: [ComponentPlan] = [picoSDK, armToolchain]
    if let picoSdkTools { all.append(picoSdkTools) }
    all.append(contentsOf: [ninja, cmake, picotool])
    return all
  }
}