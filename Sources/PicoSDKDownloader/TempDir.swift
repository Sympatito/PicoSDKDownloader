import Foundation

struct TempDir {
  let url: URL

  static func create(prefix: String) throws -> TempDir {
    let base = FileManager.default.temporaryDirectory
    let dir = base.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return TempDir(url: dir)
  }

  func cleanup() throws {
    try FileManager.default.removeItem(at: url)
  }
}