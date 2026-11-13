import Foundation

public struct ExpansionMatch: Equatable {
  public let snippet: Snippet
  public let deletionCount: Int
  public var preservesTrigger: Bool { !SnippetTemplate(snippet.content).placeholders.isEmpty }
}

public struct ExpansionMatcher {
  private var buffer = ""

  public init() {}

  public mutating func reset() {
    buffer = ""
  }

  public mutating func backspace() {
    if !buffer.isEmpty { buffer.removeLast() }
  }

  // Track only a potential shortcut, never the surrounding typed text.
  public mutating func consume(_ text: String, snippets: [Snippet]) -> ExpansionMatch? {
    guard text.count == 1, let character = text.first else {
      reset()
      return nil
    }
    if character == ";" {
      buffer = ";"
    } else if !buffer.isEmpty {
      buffer.append(character)
    } else {
      return nil
    }

    if let snippet = snippets.first(where: { $0.trigger == buffer }) {
      let preservesTrigger = !SnippetTemplate(snippet.content).placeholders.isEmpty
      let count = buffer.utf16.count - (preservesTrigger ? 0 : 1)
      reset()
      return ExpansionMatch(snippet: snippet, deletionCount: count)
    }
    if !snippets.contains(where: { $0.trigger.hasPrefix(buffer) }) {
      reset()
    }
    return nil
  }
}
