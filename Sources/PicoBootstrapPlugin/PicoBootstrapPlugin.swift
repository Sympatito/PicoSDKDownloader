import PackagePlugin
import Foundation

@main
struct PicoBootstrapPlugin: CommandPlugin {
  func performCommand(context: PluginContext, arguments: [String]) async throws {
    let tool = try context.tool(named: "pico-bootstrap")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool.path.string)
    process.arguments = arguments
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError

    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
      throw PluginError.commandFailed(Int(process.terminationStatus))
    }
  }

  enum PluginError: Error, CustomStringConvertible {
    case commandFailed(Int)

    var description: String {
      switch self {
      case .commandFailed(let code):
        return "pico-bootstrap exited with status \(code)"
      }
    }
  }
}
