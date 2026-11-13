import Foundation

public struct Snippet: Codable, Identifiable, Equatable {
  public var id: UUID
  public var title: String
  public var trigger: String
  public var content: String

  public init(id: UUID = UUID(), title: String, trigger: String, content: String) {
    self.id = id
    self.title = title
    self.trigger = trigger
    self.content = content
  }

  public static let examples = [
    Snippet(title: "Terraform formatieren", trigger: ";tfmt", content: "terraform fmt -recursive"),
    Snippet(title: "Terraform validieren", trigger: ";tval", content: "terraform validate"),
    Snippet(title: "Git-Status", trigger: ";gst", content: "git status --short"),
  ]
}

public enum SnippetValidationError: LocalizedError, Equatable {
  case emptyTitle
  case invalidTrigger
  case emptyContent
  case duplicateID
  case conflictingTrigger(String)

  public var errorDescription: String? {
    switch self {
    case .emptyTitle:
      return "Bitte einen Namen eingeben."
    case .invalidTrigger:
      return
        "Kürzel müssen mit ; beginnen, danach Buchstaben, Ziffern, - oder _ enthalten und 2 bis 64 Zeichen lang sein."
    case .emptyContent:
      return "Bitte einen einzufügenden Text eingeben."
    case .duplicateID:
      return "Die Datei enthält doppelte Eintrags-IDs."
    case .conflictingTrigger(let trigger):
      return
        "Das Kürzel überschneidet sich mit \(trigger). Kürzel dürfen nicht identisch oder der Anfang eines anderen Kürzels sein."
    }
  }
}

public enum SnippetRules {
  public static func validate(_ snippet: Snippet, among snippets: [Snippet]) throws {
    guard !snippet.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw SnippetValidationError.emptyTitle
    }
    let scalars = Array(snippet.trigger.unicodeScalars)
    let allowed = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
    guard (2...64).contains(scalars.count), scalars.first == ";",
      scalars.dropFirst().allSatisfy({ allowed.contains($0) })
    else {
      throw SnippetValidationError.invalidTrigger
    }
    guard !snippet.content.isEmpty else { throw SnippetValidationError.emptyContent }
    for other in snippets where other.id != snippet.id {
      if snippet.trigger.hasPrefix(other.trigger) || other.trigger.hasPrefix(snippet.trigger) {
        throw SnippetValidationError.conflictingTrigger(other.trigger)
      }
    }
  }

  public static func validateAll(_ snippets: [Snippet]) throws {
    guard Set(snippets.map(\.id)).count == snippets.count else {
      throw SnippetValidationError.duplicateID
    }
    for snippet in snippets {
      try validate(snippet, among: snippets)
    }
  }

  public static func search(_ snippets: [Snippet], query: String) -> [Snippet] {
    let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
    return snippets.filter { snippet in
      let fields = [snippet.title, snippet.trigger, snippet.content]
      return terms.allSatisfy { term in
        fields.contains {
          $0.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
      }
    }.sorted {
      $0.title.localizedStandardCompare($1.title) == .orderedAscending
    }
  }
}
