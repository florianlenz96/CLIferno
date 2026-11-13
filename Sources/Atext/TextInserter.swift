import AppKit
import Carbon

enum InsertionError: LocalizedError {
  case permission
  case noTarget
  case secureInput
  case clipboard
  case keyboard
  case focusChanged

  var errorDescription: String? {
    switch self {
    case .permission: return "Zum Einfügen bitte Bedienungshilfen für Atext erlauben."
    case .noTarget:
      return "Die Zielanwendung ist nicht mehr aktiv. Text bitte über die Suche erneut auswählen."
    case .secureInput:
      return "Sichere Tastatureingabe ist aktiv. In geschützte Felder wird nicht eingefügt."
    case .clipboard:
      return "Die Zwischenablage konnte nicht sicher gesichert werden. Es wurde nichts eingefügt."
    case .keyboard: return "macOS konnte die Tastatureingabe nicht erstellen."
    case .focusChanged:
      return "Das Eingabefeld hat sich geändert. Es wurde nichts eingefügt; bitte erneut auslösen."
    }
  }
}

final class TextInserter {
  static let eventMarker: Int64 = 0x41_5445_5854
  // nspasteboard.org markers: clipboard managers must not record or display this content.
  static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
  static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
  // Long enough for a busy target to process Cmd+V before the old clipboard returns.
  private static let restoreDelay: TimeInterval = 1.5
  private(set) var isBusy = false
  private var restoreWork: DispatchWorkItem?
  private var savedClipboard: [[(NSPasteboard.PasteboardType, Data)]]?
  private var ownedChangeCount: Int?

  /// Writes text to the general pasteboard, flagged so clipboard history tools skip it.
  @discardableResult
  static func writeConcealed(_ text: String, transient: Bool) -> Bool {
    let item = NSPasteboardItem()
    guard item.setString(text, forType: .string),
      item.setData(Data(), forType: concealedType)
    else { return false }
    if transient { item.setData(Data(), forType: transientType) }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    return pasteboard.writeObjects([item])
  }

  /// The focused UI element of an application, if it exposes one via Accessibility.
  static func focusedElement(of pid: pid_t) -> AXUIElement? {
    var value: CFTypeRef?
    let app = AXUIElementCreateApplication(pid)
    guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value)
      == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    return unsafeBitCast(value, to: AXUIElement.self)
  }

  func insert(
    _ text: String, deleting count: Int, into targetPID: pid_t,
    expectedFocus: AXUIElement? = nil,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    guard !isBusy else { return }
    guard AXIsProcessTrusted() else {
      completion(.failure(InsertionError.permission))
      return
    }
    guard !IsSecureEventInputEnabled() else {
      completion(.failure(InsertionError.secureInput))
      return
    }
    guard targetPID != ProcessInfo.processInfo.processIdentifier,
      NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID
    else {
      completion(.failure(InsertionError.noTarget))
      return
    }
    // Never edit a different field (e.g. another tab) than the one the trigger was typed in.
    if let expectedFocus {
      guard let current = Self.focusedElement(of: targetPID), CFEqual(current, expectedFocus)
      else {
        completion(.failure(InsertionError.focusChanged))
        return
      }
    }
    guard let source = CGEventSource(stateID: .privateState) else {
      completion(.failure(InsertionError.keyboard))
      return
    }
    var events: [CGEvent] = []
    for key in Array(repeating: CGKeyCode(51), count: count) + [CGKeyCode(9)] {
      guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
      else {
        completion(.failure(InsertionError.keyboard))
        return
      }
      let flags: CGEventFlags = key == 9 ? .maskCommand : []
      for event in [down, up] {
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
        events.append(event)
      }
    }

    restoreClipboard()
    let pasteboard = NSPasteboard.general
    var snapshot: [[(NSPasteboard.PasteboardType, Data)]] = []
    for item in pasteboard.pasteboardItems ?? [] {
      var values: [(NSPasteboard.PasteboardType, Data)] = []
      for type in item.types {
        guard let data = item.data(forType: type) else {
          completion(.failure(InsertionError.clipboard))
          return
        }
        values.append((type, data))
      }
      snapshot.append(values)
    }
    savedClipboard = snapshot
    guard Self.writeConcealed(text, transient: true) else {
      ownedChangeCount = pasteboard.changeCount
      restoreClipboard()
      completion(.failure(InsertionError.clipboard))
      return
    }
    ownedChangeCount = pasteboard.changeCount
    isBusy = true
    // Deliver only to the verified target process, not to whatever window is focused later.
    for event in events {
      event.postToPid(targetPID)
    }
    // Leave time for the target to process Cmd+V; never overwrite a newer user copy.
    let work = DispatchWorkItem { [weak self] in
      self?.restoreClipboard()
      self?.isBusy = false
      completion(.success(()))
    }
    restoreWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.restoreDelay, execute: work)
  }

  func restoreClipboard() {
    restoreWork?.cancel()
    restoreWork = nil
    defer {
      savedClipboard = nil
      ownedChangeCount = nil
    }
    guard let snapshot = savedClipboard, let changeCount = ownedChangeCount,
      NSPasteboard.general.changeCount == changeCount
    else { return }
    let items = snapshot.map { values -> NSPasteboardItem in
      let item = NSPasteboardItem()
      for (type, data) in values { item.setData(data, forType: type) }
      return item
    }
    NSPasteboard.general.clearContents()
    if !items.isEmpty { NSPasteboard.general.writeObjects(items) }
  }
}
