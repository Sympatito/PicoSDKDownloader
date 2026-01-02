import Foundation

enum Extractor {
  static func extract(archive: URL, to dest: URL) throws {
    let path = archive.path.lowercased()
    if path.hasSuffix(".zip") {
      _ = try Shell.run("unzip", ["-q", archive.path, "-d", dest.path])
      return
    }
    if path.hasSuffix(".tar.gz") || path.hasSuffix(".tgz") {
      _ = try Shell.run("tar", ["-xzf", archive.path, "-C", dest.path])
      return
    }
    if path.hasSuffix(".tar.xz") {
      _ = try Shell.run("tar", ["-xJf", archive.path, "-C", dest.path])
      return
    }
    throw PicoBootstrapError.message("Unsupported archive type: \(archive.lastPathComponent)")
  }
}
