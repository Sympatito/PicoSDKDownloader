import Foundation

public final class GitHubClient {
  private let http: HTTPClient
  public init(http: HTTPClient) { self.http = http }

  public func listReleases(owner: String, repo: String, limit: Int = 30) async throws -> [GitHubRelease] {
    let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=\(min(limit, 100))")!
    let (data, _) = try await http.get(url, headers: ["Accept": "application/vnd.github+json"])
    return try JSONDecoder().decode([GitHubRelease].self, from: data)
  }

  public func getReleaseByTag(owner: String, repo: String, tag: String) async throws -> GitHubRelease {
    let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/tags/\(tag)")!
    let (data, _) = try await http.get(url, headers: ["Accept": "application/vnd.github+json"])
    return try JSONDecoder().decode(GitHubRelease.self, from: data)
  }

  public func listTags(owner: String, repo: String, limit: Int = 30) async throws -> [String] {
    let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/tags?per_page=\(min(limit, 100))")!
    let (data, _) = try await http.get(url, headers: ["Accept": "application/vnd.github+json"])
    let tags = try JSONDecoder().decode([GitHubTag].self, from: data)
    return tags.map { $0.name }
  }
}
