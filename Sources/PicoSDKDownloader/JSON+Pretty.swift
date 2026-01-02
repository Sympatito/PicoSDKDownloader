import Foundation

extension JSONEncoder {
  static var pretty: JSONEncoder {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    return enc
  }
}
