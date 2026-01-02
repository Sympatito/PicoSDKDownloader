import Foundation

public struct HostEnvironment: Codable {
  public enum OS: String, Codable { case macos, linux }
  public enum Arch: String, Codable { case x86_64, aarch64 }

  public let os: OS
  public let arch: Arch

  public init(os: OS, arch: Arch) {
    self.os = os
    self.arch = arch
  }

  public static func detect() throws -> HostEnvironment {
    #if os(macOS)
    let os: OS = .macos
    #elseif os(Linux)
    let os: OS = .linux
    #else
    throw PicoBootstrapError.unsupportedPlatform("Only macOS and Linux are supported.")
    #endif

    // Swift reports arch via uname
    var uts = utsname()
    uname(&uts)
    var utsMachine = uts.machine

    let machine = withUnsafePointer(to: &utsMachine) {
      $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: uts.machine)) {
        String(cString: $0)
      }
    }

    let arch: Arch
    switch machine {
    case "x86_64", "amd64":
      arch = .x86_64
    case "arm64", "aarch64":
      arch = .aarch64
    default:
      throw PicoBootstrapError.unsupportedPlatform("Unsupported CPU architecture: \(machine)")
    }

    return HostEnvironment(os: os, arch: arch)
  }
}
