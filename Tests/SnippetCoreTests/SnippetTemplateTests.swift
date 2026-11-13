import XCTest

@testable import SnippetCore

final class SnippetTemplateTests: XCTestCase {
  func testTemplateMatchKeepsFullTriggerUntilConfirmation() throws {
    let snippet = Snippet(title: "New branch", trigger: ";gitnb", content: "git checkout -b $1")
    var matcher = ExpansionMatcher()
    var match: ExpansionMatch?
    for character in snippet.trigger {
      match = matcher.consume(String(character), snippets: [snippet])
    }
    let result = try XCTUnwrap(match)
    XCTAssertTrue(result.preservesTrigger)
    XCTAssertEqual(result.deletionCount, 6)
    let literal = Snippet(title: "Literal", trigger: ";literal", content: "echo $$1")
    for character in literal.trigger {
      match = matcher.consume(String(character), snippets: [literal])
    }
    let literalMatch = try XCTUnwrap(match)
    XCTAssertFalse(literalMatch.preservesTrigger)
    XCTAssertEqual(literalMatch.deletionCount, 7)
  }

  func testNewBranchUsesSameValueForBothOccurrences() throws {
    let template = SnippetTemplate(
      "git checkout main && git pull && git checkout -b $1 && git push --set-upstream origin $1")
    XCTAssertEqual(template.placeholders, ["$1"])
    XCTAssertEqual(
      try template.render(values: ["$1": "feature/login"]),
      "git checkout main && git pull && git checkout -b feature/login && git push --set-upstream origin feature/login"
    )
  }

  func testMultiplePlaceholdersSortNumericallyAndDoNotOverlap() throws {
    let template = SnippetTemplate("$10/$2/$1/$10/$99")
    XCTAssertEqual(template.placeholders, ["$1", "$2", "$10", "$99"])
    XCTAssertEqual(
      try template.render(values: ["$1": "one", "$2": "two", "$10": "ten", "$99": "last"]),
      "ten/two/one/ten/last")
  }

  func testValuesAreLiteralAndPreserveMultilineUnicodeAndWhitespace() throws {
    let template = SnippetTemplate("$1\n$2\n$1")
    XCTAssertEqual(
      try template.render(values: ["$1": "$2 $(echo example)", "$2": " Grüße\nline two "]),
      "$2 $(echo example)\n Grüße\nline two \n$2 $(echo example)")
  }

  func testMissingValuesRemainVisibleInPreviewAndBlockRendering() {
    let template = SnippetTemplate("$1 $2 $1")
    XCTAssertEqual(template.preview(values: ["$1": "branch"]), "branch $2 branch")
    for values in [["$1": "branch"], ["$1": "branch", "$2": ""]] {
      XCTAssertThrowsError(try template.render(values: values)) {
        XCTAssertEqual($0 as? TemplateError, .missingValue("$2"))
      }
    }
  }

  func testDollarEscapeAndShellVariablesRemainLiteral() throws {
    let template = SnippetTemplate("$$1 $$ $HOME ${PATH} $(pwd) $0 $01 $")
    XCTAssertTrue(template.placeholders.isEmpty)
    XCTAssertEqual(try template.render(values: [:]), "$1 $ $HOME ${PATH} $(pwd) $0 $01 $")
    let mixed = SnippetTemplate("$$1 $1 $$$2")
    XCTAssertEqual(mixed.placeholders, ["$1", "$2"])
    XCTAssertEqual(try mixed.render(values: ["$1": "a", "$2": "b"]), "$1 a $b")
  }

  func testStaticTextIsUnchangedAndTemplatePersistsInExistingFormat() throws {
    let text = "terraform fmt -recursive\n"
    XCTAssertEqual(try SnippetTemplate(text).render(values: [:]), text)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = SnippetRepository(fileURL: directory.appendingPathComponent("snippets.json"))
    let snippet = Snippet(title: "New branch", trigger: ";gitnb", content: "git checkout -b $1")
    try repository.save([snippet])
    XCTAssertEqual(try repository.load(), [snippet])
  }
}
