import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class HTTPClient {
  private let githubToken: String?

  public init(githubToken: String?) {
    self.githubToken = (githubToken?.isEmpty == false) ? githubToken : nil
  }

  public func get(_ url: URL, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
    #if os(macOS)
    // The other option is to add a restriction at the package level for macOS 13, but this then requires
    // all consumers to also restrict their packages to macOS 13, while this is host-only running code.
    // This is undesirable but provides better ergonomics. An alternative could be to provide a wrapper
    // around dataTask.
    // TODO: Provide a wrapper around dataTask for older OS versions.

    guard #available(macOS 13, *) else {
      throw PicoBootstrapError.unsupportedPlatform("macOS v13 is required for async HTTP requests.")
    }
    #endif

    let req = makeRequest(url: url, headers: headers)

    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse else {
      throw PicoBootstrapError.http("Non-HTTP response for \(url)")
    }
    guard (200..<300).contains(http.statusCode) else {
      throw PicoBootstrapError.http("GET \(url) -> \(http.statusCode)\n\(String(data: data, encoding: .utf8) ?? "")")
    }
    return (data, http)
  }

  public func download(_ url: URL, to dest: URL) async throws {
    #if os(macOS)
    // TODO: Provide a wrapper around dataTask for older OS versions.
    guard #available(macOS 13, *) else {
      throw PicoBootstrapError.unsupportedPlatform("macOS v13 is required for async HTTP requests.")
    }
    #endif

    try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

    let req = makeRequest(url: url)
    let (tmp, resp) = try await URLSession.shared.download(for: req)
    guard let http = resp as? HTTPURLResponse else {
      throw PicoBootstrapError.http("Non-HTTP response for \(url)")
    }
    guard (200..<300).contains(http.statusCode) else {
      let body = try? String(contentsOf: tmp, encoding: .utf8)
      throw PicoBootstrapError.http("GET \(url) -> \(http.statusCode)\n\(body ?? "")")
    }

    if FileManager.default.fileExists(atPath: dest.path) {
      try FileManager.default.removeItem(at: dest)
    }
    try FileManager.default.moveItem(at: tmp, to: dest)
  }

  private func makeRequest(url: URL, headers: [String: String] = [:]) -> URLRequest {
    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    if let githubToken {
      req.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
    }
    req.setValue("pico-bootstrap/0.1.0", forHTTPHeaderField: "User-Agent")
    return req
  }
}
