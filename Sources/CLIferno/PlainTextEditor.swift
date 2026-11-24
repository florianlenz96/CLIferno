import AppKit
import SwiftUI

/// Multi-line editor for snippet text that inserts exactly what is typed.
///
/// SwiftUI's `TextEditor` follows the system setting "Use smart quotes and dashes", which turns
/// `"$1"` into `„$1“` (German) or `“$1”` and `--` into `—`. That breaks shell commands, so all
/// automatic substitutions are switched off here.
struct PlainTextEditor: NSViewRepresentable {
  @Binding var text: String
  var font: NSFont = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

  func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSTextView.scrollableTextView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    guard let textView = scroll.documentView as? NSTextView else { return scroll }
    textView.disableAutomaticSubstitutions()
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.drawsBackground = false
    textView.font = font
    textView.textColor = .textColor
    textView.string = text
    textView.delegate = context.coordinator
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    context.coordinator.text = $text
    guard let textView = scroll.documentView as? NSTextView else { return }
    if textView.string != text {
      let selection = textView.selectedRanges
      textView.string = text
      let length = (text as NSString).length
      textView.selectedRanges = selection.map { value in
        let range = value.rangeValue
        let location = min(range.location, length)
        return NSValue(range: NSRange(location: location, length: min(range.length, length - location)))
      }
    }
    if textView.font != font { textView.font = font }
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var text: Binding<String>

    init(text: Binding<String>) { self.text = text }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      text.wrappedValue = textView.string
    }
  }
}

extension NSTextView {
  /// Turns off smart quotes, smart dashes, text replacement, autocorrect and the like, so typed
  /// characters are kept exactly.
  func disableAutomaticSubstitutions() {
    isAutomaticQuoteSubstitutionEnabled = false
    isAutomaticDashSubstitutionEnabled = false
    isAutomaticTextReplacementEnabled = false
    isAutomaticSpellingCorrectionEnabled = false
    isAutomaticLinkDetectionEnabled = false
    isAutomaticDataDetectionEnabled = false
    isAutomaticTextCompletionEnabled = false
    smartInsertDeleteEnabled = false
  }
}
