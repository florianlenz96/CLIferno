import Foundation

public enum TemplateError: LocalizedError, Equatable {
  case missingValue(String)

  public var errorDescription: String? {
    switch self {
    case .missingValue(let placeholder):
      return "Bitte einen Wert für \(placeholder) eingeben."
    }
  }
}

public struct SnippetTemplate {
  private enum Part {
    case text(String)
    case placeholder(String)
  }

  private let parts: [Part]
  public let placeholders: [String]

  public init(_ content: String) {
    let characters = Array(content)
    var parts: [Part] = []
    var keys = Set<String>()
    var literal = ""
    var index = 0
    while index < characters.count {
      let character = characters[index]
      guard character == "$", index + 1 < characters.count else {
        literal.append(character)
        index += 1
        continue
      }
      let next = characters[index + 1]
      if next == "$" {
        literal.append("$")
        index += 2
      } else if ("1"..."9").contains(String(next)) {
        var end = index + 2
        while end < characters.count && ("0"..."9").contains(String(characters[end])) {
          end += 1
        }
        if !literal.isEmpty {
          parts.append(.text(literal))
          literal = ""
        }
        let key = String(characters[index..<end])
        parts.append(.placeholder(key))
        keys.insert(key)
        index = end
      } else {
        literal.append(character)
        index += 1
      }
    }
    if !literal.isEmpty { parts.append(.text(literal)) }
    self.parts = parts
    placeholders = keys.sorted {
      if $0.count != $1.count { return $0.count < $1.count }
      return $0 < $1
    }
  }

  public func preview(values: [String: String]) -> String {
    parts.map { part in
      switch part {
      case .text(let text): return text
      case .placeholder(let key):
        guard let value = values[key], !value.isEmpty else { return key }
        return value
      }
    }.joined()
  }

  public func render(values: [String: String]) throws -> String {
    for key in placeholders {
      guard let value = values[key], !value.isEmpty else {
        throw TemplateError.missingValue(key)
      }
    }
    // Render parsed parts once so a value containing $1 remains literal input.
    return preview(values: values)
  }
}
