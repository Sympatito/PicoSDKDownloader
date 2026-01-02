import Foundation

/// Simple INI parser for supportedToolchains.ini format.
/// Parses sections like [14_2_Rel1] with key=value pairs.
struct INIParser {
  /// Parse INI content into a dictionary of [section: [key: value]]
  static func parse(_ content: String) -> [String: [String: String]] {
    var result: [String: [String: String]] = [:]
    var currentSection: String?
    
    for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      
      // Skip empty lines and comments
      guard !trimmed.isEmpty, !trimmed.hasPrefix(";"), !trimmed.hasPrefix("#") else {
        continue
      }
      
      // Check for section header [section_name]
      if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
        let sectionName = String(trimmed.dropFirst().dropLast())
        currentSection = sectionName
        result[sectionName] = [:]
        continue
      }
      
      // Parse key=value pairs
      if let eqIndex = trimmed.firstIndex(of: "="), let section = currentSection {
        let key = String(trimmed[..<eqIndex]).trimmingCharacters(in: .whitespaces)
        let value = String(trimmed[trimmed.index(after: eqIndex)...]).trimmingCharacters(in: .whitespaces)
        result[section]?[key] = value
      }
    }
    
    return result
  }
}
