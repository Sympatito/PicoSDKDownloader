import Foundation

enum Shell {
  @discardableResult
  static func run(_ executable: String, _ args: [String], cwd: URL? = nil) throws -> String {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proc.arguments = [executable] + args
    if let cwd { proc.currentDirectoryURL = cwd }

    let out = Pipe()
    let err = Pipe()
    proc.standardOutput = out
    proc.standardError = err

    try proc.run()
    proc.waitUntilExit()

    let outData = out.fileHandleForReading.readDataToEndOfFile()
    let errData = err.fileHandleForReading.readDataToEndOfFile()
    let stdout = String(data: outData, encoding: .utf8) ?? ""
    let stderr = String(data: errData, encoding: .utf8) ?? ""

    if proc.terminationStatus != 0 {
      throw PicoBootstrapError.commandFailed("\(executable) \(args.joined(separator: " "))\n\(stderr)\n\(stdout)")
    }
    return stdout
  }
}