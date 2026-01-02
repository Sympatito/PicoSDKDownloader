import Foundation

extension JSONEncoder {
  public static var pretty: JSONEncoder {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    return enc
  }
}
