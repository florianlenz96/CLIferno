import AppKit
import Combine
import SnippetCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var model: AppModel!
  private var managerWindow: NSWindow!
  private var searchController: SearchController!
  private var templateController: TemplateController!
  private var statusItem: NSStatusItem!
  private var pauseItem: NSMenuItem!
  private var appearanceItems: [AppearanceMode: NSMenuItem] = [:]
  private var subscriptions = Set<AnyCancellable>()
  private var smokeDirectory: URL?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let smokeTest = CommandLine.arguments.contains("--smoke-test")
    if smokeTest {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "CLIferno-smoke-\(UUID().uuidString)")
      smokeDirectory = directory
      model = AppModel(
        repository: SnippetRepository(fileURL: directory.appendingPathComponent("snippets.json")),
        monitorPermissions: false)
    } else {
      model = AppModel()
    }
    installMainMenu()
    searchController = SearchController(model: model)
    templateController = TemplateController()
    model.openSearch = { [weak self] target in self?.searchController.show(target: target) }
    model.openTemplate = { [weak self] snippet, target, actionTitle, completion in
      self?.templateController.show(
        snippet: snippet, target: target, actionTitle: actionTitle,
        completion: completion)
    }
    managerWindow = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 690),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    managerWindow.title = "CLIferno – Deine Textkürzel"
    managerWindow.isReleasedWhenClosed = false
    managerWindow.contentView = NSHostingView(rootView: ManagerView(model: model))
    managerWindow.center()

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.image = NSImage(
      systemSymbolName: "flame", accessibilityDescription: "CLIferno")
    let menu = NSMenu()
    addMenuItem("Einträge verwalten …", action: #selector(showManager), to: menu)
    addMenuItem("Text suchen …", action: #selector(showSearch), to: menu)
    menu.addItem(.separator())
    pauseItem = addMenuItem("Ersetzung pausieren", action: #selector(togglePause), to: menu)
    let appearanceMenu = NSMenu()
    for mode in AppearanceMode.allCases {
      let item = addMenuItem(mode.title, action: #selector(selectAppearance(_:)), to: appearanceMenu)
      item.representedObject = mode.rawValue
      appearanceItems[mode] = item
    }
    let appearanceItem = NSMenuItem(title: "Darstellung", action: nil, keyEquivalent: "")
    appearanceItem.submenu = appearanceMenu
    menu.addItem(appearanceItem)
    menu.addItem(.separator())
    addMenuItem("CLIferno beenden", action: #selector(quit), to: menu)
    statusItem.menu = menu
    model.$paused.combineLatest(model.$monitorRunning).sink { [weak self] paused, running in
      self?.pauseItem.state = paused ? .on : .off
      self?.statusItem.button?.toolTip =
        paused ? "CLIferno – pausiert" : (running ? "CLIferno – aktiv" : "CLIferno – Berechtigungen fehlen")
    }.store(in: &subscriptions)
    model.$appearance.sink { [weak self] current in
      self?.appearanceItems.forEach { mode, item in item.state = mode == current ? .on : .off }
    }.store(in: &subscriptions)
    showManager()

    if smokeTest {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
        managerWindow.contentView?.layoutSubtreeIfNeeded()
        precondition(managerWindow.isVisible, "Manager window did not open")
        precondition(model.snippets.count == 3 && model.storageAvailable, "Initial storage failed")
        searchController.show(target: nil)
        searchController.searchField.stringValue = "recursive"
        searchController.controlTextDidChange(
          Notification(name: NSControl.textDidChangeNotification))
        searchController.panel.contentView?.layoutSubtreeIfNeeded()
        precondition(searchController.panel.isVisible, "Search panel did not open")
        precondition(
          searchController.panel.firstResponder is NSTextView, "Search field is not focused")
        let filteredCount = searchController.numberOfRows(in: NSTableView())
        precondition(filteredCount == 1, "Native search did not filter its results")
        let testSnippet = Snippet(title: "Smoke", trigger: ";smoke", content: "line one\nline two")
        precondition(model.save(testSnippet), "Native model could not save")
        precondition(
          (try? model.repository.load())?.contains(testSnippet) == true, "Save did not persist")
        model.delete(testSnippet.id)
        precondition(model.snippets.count == 3, "Native model could not delete")
        searchController.searchField.stringValue = "no matching result"
        searchController.controlTextDidChange(
          Notification(name: NSControl.textDidChangeNotification))
        precondition(searchController.numberOfRows(in: NSTableView()) == 0, "Empty search failed")
        precondition(
          NSApp.mainMenu?.items.contains(where: { $0.title == "Bearbeiten" }) == true,
          "Standard text editing menu is missing")
        let originalAppearance = UserDefaults.standard.string(forKey: AppearanceMode.defaultsKey)
        for mode in [AppearanceMode.dark, .light, .system] {
          model.appearance = mode
          precondition(NSApp.appearance?.name == mode.nsAppearance?.name, "Appearance not applied")
          precondition(appearanceItems[mode]?.state == .on, "Appearance menu not updated")
        }
        UserDefaults.standard.set(originalAppearance, forKey: AppearanceMode.defaultsKey)
        smokeTestTemplates()
      }
    }
  }

  private func smokeTestTemplates() {
    searchController.panel.orderOut(nil)
    let snippet = Snippet(
      title: "Git new branch", trigger: ";gitnb",
      content:
        "git checkout main && git pull && git checkout -b $1 && git push --set-upstream origin $1")
    var completed = false
    templateController.show(snippet: snippet, target: nil, actionTitle: "Einfügen") { text in
      precondition(
        text
          == "git checkout main && git pull && git checkout -b feature/login && git push --set-upstream origin feature/login",
        "Template confirmation rendered the wrong text")
      completed = true
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
      guard let form = templateController.form, let panel = templateController.panel else {
        preconditionFailure("Template prompt did not open")
      }
      panel.contentView?.layoutSubtreeIfNeeded()
      precondition(panel.isVisible, "Template prompt is not visible")
      let singleParameterSize = panel.contentRect(forFrameRect: panel.frame).size
      precondition(
        singleParameterSize.width == 620 && singleParameterSize.height < 300,
        "Single-parameter popup is not compact")
      precondition(panel.firstResponder is NSTextView, "Placeholder field is not focused")
      precondition(form.template.placeholders == ["$1"], "Repeated placeholder has multiple fields")
      precondition(!form.canConfirm, "Empty placeholders must block confirmation")
      templateController.confirm()
      precondition(!completed && templateController.isPresenting, "Empty form was submitted")
      form.values["$1"] = "feature/login"
      precondition(form.canConfirm && !form.preview.contains("$1"), "Live preview did not update")
      templateController.confirm()
      precondition(completed && !templateController.isPresenting, "Confirmation did not finish")
      var cancelled = false
      templateController.show(snippet: snippet, target: nil, actionTitle: "Einfügen") { text in
        precondition(text == nil, "Cancellation returned text to insert")
        cancelled = true
      }
      templateController.cancel()
      precondition(cancelled && !templateController.isPresenting, "Cancellation did not finish")
      let manyParameters = Snippet(
        title: "Multiple parameters", trigger: ";many",
        content: (1...12).map { "$\($0)" }.joined(separator: " "))
      templateController.show(snippet: manyParameters, target: nil, actionTitle: "Einfügen") {
        text in
        precondition(text == nil, "Multi-parameter cancellation returned text")
      }
      templateController.panel?.contentView?.layoutSubtreeIfNeeded()
      guard let multiplePanel = templateController.panel else {
        preconditionFailure("Multi-parameter popup did not open")
      }
      let multipleSize = multiplePanel.contentRect(forFrameRect: multiplePanel.frame).size
      precondition(
        multipleSize.width == 620 && multipleSize.height <= 400,
        "Many parameters must scroll instead of enlarging the popup")
      precondition(
        templateController.form?.template.placeholders.count == 12,
        "Compact popup lost parameters")
      templateController.cancel()
      model.copy(snippet)
      precondition(model.isPreparingTemplate, "Copy bypassed the template prompt")
      templateController.cancel()
      precondition(!model.isPreparingTemplate, "Cancellation left the monitor busy")
      // A fake target tests prompt routing without sending any input to another app.
      model.insert(snippet, deleting: 6, targetPID: ProcessInfo.processInfo.processIdentifier)
      precondition(model.isPreparingTemplate, "Automatic insertion bypassed the template prompt")
      templateController.cancel()
      precondition(!model.isPreparingTemplate, "Automatic cancellation left the monitor busy")
      print(
        "SMOKE PASS: compact single/multiple-parameter popup, field focus, preview, confirmation, cancellation, copy/insertion routing, manager/search/storage"
      )
      NSApp.terminate(nil)
    }
  }

  @discardableResult
  private func addMenuItem(_ title: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    menu.addItem(item)
    return item
  }

  @objc private func showManager() {
    NSApp.activate(ignoringOtherApps: true)
    managerWindow.makeKeyAndOrderFront(nil)
  }

  @objc private func showSearch() {
    searchController.show(target: NSWorkspace.shared.frontmostApplication)
  }

  @objc private func togglePause() { model.paused.toggle() }
  @objc private func selectAppearance(_ sender: NSMenuItem) {
    guard let raw = sender.representedObject as? String,
      let mode = AppearanceMode(rawValue: raw)
    else { return }
    model.appearance = mode
  }
  @objc private func quit() { NSApp.terminate(nil) }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard model?.hasUnsavedChanges == true else { return .terminateNow }
    let alert = NSAlert()
    alert.messageText = "CLIferno beenden und ungespeicherte Änderungen verwerfen?"
    alert.addButton(withTitle: "Weiter bearbeiten")
    alert.addButton(withTitle: "Beenden")
    return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
  }

  private func installMainMenu() {
    let mainMenu = NSMenu()
    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    addMenuItem("Einträge verwalten …", action: #selector(showManager), to: appMenu)
    let quitItem = addMenuItem("CLIferno beenden", action: #selector(quit), to: appMenu)
    quitItem.keyEquivalent = "q"
    appItem.submenu = appMenu
    mainMenu.addItem(appItem)

    let editItem = NSMenuItem(title: "Bearbeiten", action: nil, keyEquivalent: "")
    let editMenu = NSMenu(title: "Bearbeiten")
    for (title, action, key, modifiers) in [
      ("Rückgängig", Selector(("undo:")), "z", NSEvent.ModifierFlags.command),
      ("Wiederholen", Selector(("redo:")), "z", [.command, .shift]),
      ("Ausschneiden", #selector(NSText.cut(_:)), "x", .command),
      ("Kopieren", #selector(NSText.copy(_:)), "c", .command),
      ("Einfügen", #selector(NSText.paste(_:)), "v", .command),
      ("Alles auswählen", #selector(NSText.selectAll(_:)), "a", .command),
    ] {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
      item.keyEquivalentModifierMask = modifiers
      editMenu.addItem(item)
    }
    editItem.submenu = editMenu
    mainMenu.addItem(editItem)
    NSApp.mainMenu = mainMenu
  }

  func applicationWillTerminate(_ notification: Notification) {
    model?.shutdown()
    if let smokeDirectory { try? FileManager.default.removeItem(at: smokeDirectory) }
  }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
