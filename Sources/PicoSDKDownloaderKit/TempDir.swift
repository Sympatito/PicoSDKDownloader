import Foundation

struct TempDir {
  let url: URL

  static func create(prefix: String) throws -> TempDir {
    let fm = FileManager.default
    do {
      let dir = try fm.url(
        for: .itemReplacementDirectory,
        in: .userDomainMask,
        appropriateFor: fm.temporaryDirectory,
        create: true
      )
      return TempDir(url: dir)
    } catch {
      let fallback = fm.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
      try fm.createDirectory(at: fallback, withIntermediateDirectories: true)
      return TempDir(url: fallback)
    }
  }

  func cleanup() throws {
    try FileManager.default.removeItem(at: url)
  }
}
