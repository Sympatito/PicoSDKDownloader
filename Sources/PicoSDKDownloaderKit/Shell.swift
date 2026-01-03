import Foundation

enum Shell {
  @discardableResult
  static func run(_ executable: String, _ args: [String], cwd: URL? = nil) throws {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proc.arguments = [executable] + args
    if let cwd { proc.currentDirectoryURL = cwd }

    try proc.run()
    proc.waitUntilExit()

    if proc.terminationStatus != 0 {
      throw PicoBootstrapError.commandFailed("\(executable) \(args.joined(separator: " "))\n\(stderr)\n\(stdout)")
    }
  }
}
