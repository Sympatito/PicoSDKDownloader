import Foundation

public struct GitHubRelease: Codable {
  public struct Asset: Codable {
    public let name: String
    public let browser_download_url: String
    public let size: Int?
  }
  public let tag_name: String
  public let prerelease: Bool
  public let draft: Bool
  public let assets: [Asset]
}

public struct GitHubTag: Codable {
  public let name: String
}
