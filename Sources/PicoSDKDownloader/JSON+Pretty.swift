import Foundation

extension JSONEncoder {
  static var pretty: JSONEncoder {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    return enc
  }
}

extension JSONDecoder {
  static var standard: JSONDecoder {
    JSONDecoder()
  }
}

extension JSONEncoder {
  func encode<T: Encodable>(_ value: T) throws -> Data {
    try self.encode(value)
  }
}