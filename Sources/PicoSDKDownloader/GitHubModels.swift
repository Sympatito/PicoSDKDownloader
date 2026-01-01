import Foundation

struct GitHubRelease: Codable {
  struct Asset: Codable {
    let name: String
    let browser_download_url: String
    let size: Int?
  }
  let tag_name: String
  let prerelease: Bool
  let draft: Bool
  let assets: [Asset]
}

struct GitHubTag: Codable {
  let name: String
}