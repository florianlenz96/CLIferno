import AppKit
import Carbon
import SnippetCore

private let keyboardCallback: CGEventTapCallBack = { _, type, event, userInfo in
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()
  return monitor.handle(type: type, event: event)
}

final class KeyboardMonitor {
  var snippets: [Snippet] = [] {
    didSet { matcher.reset() }
  }
  var isPaused = false {
    didSet { matcher.reset() }
  }
  var onSearch: ((NSRunningApplication) -> Void)?
  var onExpansion: ((Snippet, Int, pid_t) -> Void)?
  var isInsertionBusy: () -> Bool = { false }
  var onTapStateChange: ((Bool) -> Void)?

  private var matcher = ExpansionMatcher()
  private var tap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var workspaceObserver: NSObjectProtocol?
  var isRunning: Bool { tap.map(CGEvent.tapIsEnabled(tap:)) ?? false }

  init() {
    workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.matcher.reset() }
  }

  deinit {
    stop()
    if let workspaceObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
    }
  }

  func start() {
    guard tap == nil else {
      if let tap, !CGEvent.tapIsEnabled(tap: tap) {
        matcher.reset()
        CGEvent.tapEnable(tap: tap, enable: true)
      }
      return
    }
    let mask = [CGEventType.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
      .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
    guard
      let newTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
        eventsOfInterest: mask, callback: keyboardCallback,
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
    else {
      onTapStateChange?(false)
      return
    }
    tap = newTap
    runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: newTap, enable: true)
    onTapStateChange?(isRunning)
  }

  func stop() {
    if let tap {
      CGEvent.tapEnable(tap: tap, enable: false)
      CFMachPortInvalidate(tap)
    }
    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }
    runLoopSource = nil
    tap = nil
    matcher.reset()
    onTapStateChange?(false)
  }

  fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      matcher.reset()
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      onTapStateChange?(isRunning)
      return Unmanaged.passUnretained(event)
    }
    guard event.getIntegerValueField(.eventSourceUserData) != TextInserter.eventMarker else {
      return Unmanaged.passUnretained(event)
    }
    guard type == .keyDown else {
      matcher.reset()
      return Unmanaged.passUnretained(event)
    }
    guard !IsSecureEventInputEnabled(), !isInsertionBusy(),
      let target = NSWorkspace.shared.frontmostApplication,
      target.processIdentifier != ProcessInfo.processInfo.processIdentifier
    else {
      matcher.reset()
      return Unmanaged.passUnretained(event)
    }
    let modifiers = event.flags.intersection([
      .maskCommand, .maskControl, .maskAlternate, .maskShift,
    ])
    let key = event.getIntegerValueField(.keyboardEventKeycode)
    if key == 49 && modifiers == [.maskControl, .maskAlternate] {
      matcher.reset()
      if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
        DispatchQueue.main.async { [weak self] in self?.onSearch?(target) }
      }
      return nil
    }
    guard !isPaused, modifiers.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty
    else {
      matcher.reset()
      return Unmanaged.passUnretained(event)
    }
    if key == 51 {
      matcher.backspace()
      return Unmanaged.passUnretained(event)
    }
    // Navigation, Return, Escape and Tab invalidate the cursor-relative shortcut.
    guard ![36, 48, 53, 76, 115, 116, 117, 119, 121, 123, 124, 125, 126].contains(key) else {
      matcher.reset()
      return Unmanaged.passUnretained(event)
    }
    var characters = [UniChar](repeating: 0, count: 8)
    var length = 0
    event.keyboardGetUnicodeString(
      maxStringLength: characters.count, actualStringLength: &length,
      unicodeString: &characters)
    let text = String(utf16CodeUnits: characters, count: length)
    if let match = matcher.consume(text, snippets: snippets) {
      DispatchQueue.main.async { [weak self] in
        self?.onExpansion?(match.snippet, match.deletionCount, target.processIdentifier)
      }
      // Keep the entire trigger in place until a template has been confirmed.
      return match.preservesTrigger ? Unmanaged.passUnretained(event) : nil
    }
    return Unmanaged.passUnretained(event)
  }
}
