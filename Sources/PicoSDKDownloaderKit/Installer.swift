import Foundation

public final class Installer {
  private let env: HostEnvironment
  private let http: HTTPClient

  public init(env: HostEnvironment, http: HTTPClient) {
    self.env = env
    self.http = http
  }

  public func installPicoSDK(plan: InstallPlan, root: URL) async throws {
    let dest = root.appendingPathComponent(plan.picoSDK.installPathRelativeToRoot, isDirectory: true)
    if FileManager.default.fileExists(atPath: dest.path) {
      print("Pico SDK already exists at \(dest.path) (skipping)")
      return
    }
    try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

    // clone into dest
    print("Cloning pico-sdk \(plan.request.sdkVersion) into \(dest.path)")
    try Shell.run("git", ["clone", "--depth", "1", "--branch", plan.request.sdkVersion, "https://github.com/raspberrypi/pico-sdk.git", dest.path])
  }

  public func installArmToolchain(plan: InstallPlan, root: URL) async throws {
    let c = plan.armToolchain
    let dest = root.appendingPathComponent(c.installPathRelativeToRoot, isDirectory: true)
    if FileManager.default.fileExists(atPath: dest.path) {
      print("ARM toolchain already exists at \(dest.path) (skipping)")
      return
    }
    guard let urlStr = c.downloadURL, let url = URL(string: urlStr) else {
      throw PicoBootstrapError.message("Missing toolchain download URL in plan")
    }

    let tmp = try TempDir.create(prefix: "pico-bootstrap-toolchain")
    defer { try? tmp.cleanup() }

    let archive = tmp.url.appendingPathComponent("toolchain.\(c.archiveType ?? "tar.xz")")
    print("Downloading toolchain: \(urlStr)")
    try await http.download(url, to: archive)

    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    print("Extracting toolchain into \(dest.path)")
    try Extractor.extract(archive: archive, to: dest)
    try flattenSingleDirectoryIfNeeded(at: dest)
  }

  public func installPicoSdkTools(plan: InstallPlan, root: URL) async throws {
    guard let c = plan.picoSdkTools else { return }
    let dest = root.appendingPathComponent(c.installPathRelativeToRoot, isDirectory: true)
    if FileManager.default.fileExists(atPath: dest.path) {
      print("pico-sdk-tools already exists at \(dest.path) (skipping)")
      return
    }
    guard let urlStr = c.downloadURL, let url = URL(string: urlStr) else {
      throw PicoBootstrapError.message("Missing pico-sdk-tools download URL in plan")
    }

    let tmp = try TempDir.create(prefix: "pico-bootstrap-tools")
    defer { try? tmp.cleanup() }

    let ext = c.archiveType ?? "zip"
    let archive = tmp.url.appendingPathComponent("pico-sdk-tools.\(ext)")
    print("Downloading pico-sdk-tools: \(urlStr)")
    try await http.download(url, to: archive)

    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    print("Extracting pico-sdk-tools into \(dest.path)")
    try Extractor.extract(archive: archive, to: dest)
  }

  public func installCMake(plan: InstallPlan, root: URL) async throws {
    let c = plan.cmake
    let dest = root.appendingPathComponent(c.installPathRelativeToRoot, isDirectory: true)
    if FileManager.default.fileExists(atPath: dest.path) {
      print("CMake already exists at \(dest.path) (skipping)")
      return
    }
    guard let urlStr = c.downloadURL, let url = URL(string: urlStr) else {
      throw PicoBootstrapError.message("Missing CMake download URL in plan")
    }

    let tmp = try TempDir.create(prefix: "pico-bootstrap-cmake")
    defer { try? tmp.cleanup() }

    let archive = tmp.url.appendingPathComponent("cmake.\(c.archiveType ?? "tar.gz")")
    print("Downloading CMake: \(urlStr)")
    try await http.download(url, to: archive)

    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    print("Extracting CMake into \(dest.path)")
    try Extractor.extract(archive: archive, to: dest)
    try flattenSingleDirectoryIfNeeded(at: dest)

    // pico-vscode creates a symlink on macOS for CMake.app/Contents/bin -> bin
    if env.os == .macos {
      let cmakeAppBin = dest.appendingPathComponent("CMake.app/Contents/bin", isDirectory: true)
      let bin = dest.appendingPathComponent("bin", isDirectory: true)
      if FileManager.default.fileExists(atPath: cmakeAppBin.path),
         !FileManager.default.fileExists(atPath: bin.path) {
        try FileManager.default.createSymbolicLink(at: bin, withDestinationURL: cmakeAppBin)
      }
    }
  }

  public func installNinja(plan: InstallPlan, root: URL) async throws {
    let c = plan.ninja
    let dest = root.appendingPathComponent(c.installPathRelativeToRoot, isDirectory: true)
    if FileManager.default.fileExists(atPath: dest.path) {
      print("Ninja already exists at \(dest.path) (skipping)")
      return
    }
    guard let urlStr = c.downloadURL, let url = URL(string: urlStr) else {
      throw PicoBootstrapError.message("Missing Ninja download URL in plan")
    }

    let tmp = try TempDir.create(prefix: "pico-bootstrap-ninja")
    defer { try? tmp.cleanup() }

    let archive = tmp.url.appendingPathComponent("ninja.zip")
    print("Downloading Ninja: \(urlStr)")
    try await http.download(url, to: archive)

    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    print("Extracting Ninja into \(dest.path)")
    try Extractor.extract(archive: archive, to: dest)
  }

  public func installPicotool(plan: InstallPlan, root: URL) async throws {
    let c = plan.picotool
    let dest = root.appendingPathComponent(c.installPathRelativeToRoot, isDirectory: true)
    if FileManager.default.fileExists(atPath: dest.path) {
      print("Picotool already exists at \(dest.path) (skipping)")
      return
    }
    guard let urlStr = c.downloadURL, let url = URL(string: urlStr) else {
      throw PicoBootstrapError.message("Missing picotool download URL in plan")
    }

    let tmp = try TempDir.create(prefix: "pico-bootstrap-picotool")
    defer { try? tmp.cleanup() }

    let ext = c.archiveType ?? "zip"
    let archive = tmp.url.appendingPathComponent("picotool.\(ext)")
    print("Downloading picotool: \(urlStr)")
    try await http.download(url, to: archive)

    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    print("Extracting picotool into \(dest.path)")
    try Extractor.extract(archive: archive, to: dest)
  }

  private func flattenSingleDirectoryIfNeeded(at directory: URL) throws {
    let fm = FileManager.default
    let contents = try fm.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )
    guard contents.count == 1 else { return }
    let child = contents[0]
    let values = try child.resourceValues(forKeys: [.isDirectoryKey])
    guard values.isDirectory == true else { return }

    let childContents = try fm.contentsOfDirectory(at: child, includingPropertiesForKeys: nil)
    for item in childContents {
      let target = directory.appendingPathComponent(item.lastPathComponent)
      try fm.moveItem(at: item, to: target)
    }
    try fm.removeItem(at: child)
  }
}
