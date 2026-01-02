import Foundation

public enum ComponentId: String, Codable {
  case picoSDK = "pico-sdk"
  case armToolchain = "arm-toolchain"
  case picoSdkTools = "pico-sdk-tools"
  case cmake = "cmake"
  case ninja = "ninja"
  case picotool = "picotool"
  case openocd = "openocd"
}

public struct InstallRequest: Codable {
  public var sdkVersion: String
  public var armToolchainVersion: String  // e.g. 14_2_Rel1
  public var cmakeVersion: String         // e.g. 3.31.5
  public var ninjaVersion: String         // e.g. 1.12.1
  public var picotoolVersion: String      // e.g. 2.2.0-a4
  public var openocdVersion: String       // e.g. 0.12.0+dev
  public var includePicoSdkTools: Bool

  public init(
    sdkVersion: String,
    armToolchainVersion: String,
    cmakeVersion: String,
    ninjaVersion: String,
    picotoolVersion: String,
    openocdVersion: String,
    includePicoSdkTools: Bool
  ) {
    self.sdkVersion = sdkVersion
    self.armToolchainVersion = armToolchainVersion
    self.cmakeVersion = cmakeVersion
    self.ninjaVersion = ninjaVersion
    self.picotoolVersion = picotoolVersion
    self.openocdVersion = openocdVersion
    self.includePicoSdkTools = includePicoSdkTools
  }
}

public struct ComponentPlan: Codable {
  public let id: ComponentId
  public let version: String
  public let installPathRelativeToRoot: String
  public let downloadURL: String?     // nil for git-based installs
  public let archiveType: String?     // "zip" | "tar.gz" | "tar.xz" | nil
  public let notes: String?
}

public struct InstallPlan: Codable {
  public let env: HostEnvironment
  public let request: InstallRequest
  public let picoSDK: ComponentPlan
  public let armToolchain: ComponentPlan
  public let picoSdkTools: ComponentPlan?
  public let cmake: ComponentPlan
  public let ninja: ComponentPlan
  public let picotool: ComponentPlan
  public let openocd: ComponentPlan

  public var prettyDescription: String {
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

  public var componentsInOrder: [ComponentPlan] {
    var all: [ComponentPlan] = [picoSDK, armToolchain]
    if let picoSdkTools { all.append(picoSdkTools) }
    all.append(contentsOf: [ninja, cmake, picotool, openocd])
    return all
  }
}
