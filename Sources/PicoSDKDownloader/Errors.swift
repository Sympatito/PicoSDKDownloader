import Foundation

enum PicoBootstrapError: Error, CustomStringConvertible {
  case message(String)
  case unsupportedPlatform(String)
  case http(String)
  case notFound(String)
  case commandFailed(String)

  var description: String {
    switch self {
    case .message(let s): return s
    case .unsupportedPlatform(let s): return "Unsupported platform: \(s)"
    case .http(let s): return "HTTP error: \(s)"
    case .notFound(let s): return "Not found: \(s)"
    case .commandFailed(let s): return "Command failed: \(s)"
    }
  }
}