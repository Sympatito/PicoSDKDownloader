import Foundation

final class HTTPClient {
  private let githubToken: String?

  init(githubToken: String?) {
    self.githubToken = (githubToken?.isEmpty == false) ? githubToken : nil
  }

  func get(_ url: URL, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    if let githubToken {
      req.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
    }
    req.setValue("pico-bootstrap/0.1.0", forHTTPHeaderField: "User-Agent")

    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse else {
      throw PicoBootstrapError.http("Non-HTTP response for \(url)")
    }
    guard (200..<300).contains(http.statusCode) else {
      throw PicoBootstrapError.http("GET \(url) -> \(http.statusCode)\n\(String(data: data, encoding: .utf8) ?? "")")
    }
    return (data, http)
  }

  func download(_ url: URL, to dest: URL) async throws {
    try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

    // Simple download; for progress you can extend with URLSessionDownloadDelegate.
    let (data, _) = try await get(url)
    try data.write(to: dest, options: [.atomic])
  }
}