import AppKit
import Combine
import SnippetCore
import SwiftUI

final class TemplateForm: ObservableObject {
  let snippet: Snippet
  let template: SnippetTemplate
  @Published var values: [String: String] = [:]

  init(snippet: Snippet) {
    self.snippet = snippet
    template = SnippetTemplate(snippet.content)
  }

  var preview: String { template.preview(values: values) }
  var canConfirm: Bool { (try? template.render(values: values)) != nil }
}

private final class TemplatePanel: NSPanel {
  var onCancel: (() -> Void)?

  override func cancelOperation(_ sender: Any?) { onCancel?() }
}

final class TemplateController: NSObject, NSWindowDelegate {
  private(set) var panel: NSPanel?
  private(set) var form: TemplateForm?
  private var completion: ((String?) -> Void)?
  private var target: NSRunningApplication?
  private var activationWork: DispatchWorkItem?
  private var generation = UUID()
  var isPresenting: Bool { completion != nil }

  func show(
    snippet: Snippet, target: NSRunningApplication?, actionTitle: String,
    completion: @escaping (String?) -> Void
  ) {
    guard !isPresenting else { return }
    self.target = target
    self.completion = completion
    let form = TemplateForm(snippet: snippet)
    self.form = form
    let fieldHeight = CGFloat(min(form.template.placeholders.count, 4)) * 36
    let panel = TemplatePanel(
      contentRect: NSRect(x: 0, y: 0, width: 620, height: 230 + fieldHeight),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered, defer: false)
    self.panel = panel
    panel.title = "Atext – Parameter"
    panel.isReleasedWhenClosed = false
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.hidesOnDeactivate = true
    panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    panel.delegate = self
    panel.onCancel = { [weak self] in self?.cancel() }
    panel.contentView = NSHostingView(
      rootView: TemplateView(
        form: form, actionTitle: actionTitle,
        confirm: { [weak self] in self?.confirm() },
        cancel: { [weak self] in self?.cancel() }))
    panel.center()
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
  }

  func confirm() {
    guard let form, let text = try? form.template.render(values: form.values) else { return }
    finish(text)
  }

  func cancel() { finish(nil) }

  private func finish(_ text: String?) {
    guard let completion else { return }
    self.completion = nil
    panel?.orderOut(nil)
    panel = nil
    form = nil
    let target = self.target
    self.target = nil
    generation = UUID()
    activationWork?.cancel()
    activationWork = nil
    // Cancellation never edits the target, even if it has disappeared.
    guard let text else {
      target?.activate(options: [])
      completion(nil)
      return
    }
    guard let target else {
      completion(text)
      return
    }
    let token = generation
    activate(target: target, attempts: 20, token: token) { completion($0 ? text : nil) }
  }

  private func activate(
    target: NSRunningApplication, attempts: Int, token: UUID,
    completion: @escaping (Bool) -> Void
  ) {
    guard token == generation else { return }
    guard !target.isTerminated, attempts > 0 else {
      completion(false)
      return
    }
    if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
      completion(true)
      return
    }
    if attempts == 20 { target.activate(options: []) }
    let work = DispatchWorkItem { [weak self] in
      self?.activate(target: target, attempts: attempts - 1, token: token, completion: completion)
    }
    activationWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
  }

  func windowWillClose(_ notification: Notification) { cancel() }

  func windowDidResignKey(_ notification: Notification) {
    // Switching to another window invalidates the cursor-relative replacement.
    if isPresenting { cancel() }
  }
}

private struct TemplateView: View {
  @ObservedObject var form: TemplateForm
  let actionTitle: String
  let confirm: () -> Void
  let cancel: () -> Void
  @FocusState private var focused: String?
  private var fieldHeight: CGFloat { CGFloat(min(form.template.placeholders.count, 4)) * 36 }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(form.snippet.title).font(.headline).lineLimit(1)
        Spacer()
        Text(form.snippet.trigger)
          .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(form.template.placeholders, id: \.self) { key in
            HStack {
              Text(key).font(.system(.body, design: .monospaced)).frame(
                width: 40, alignment: .leading)
              TextField(
                "Wert für \(key)",
                text: Binding(
                  get: { form.values[key] ?? "" }, set: { form.values[key] = $0 })
              )
              .textFieldStyle(.roundedBorder)
              .focused($focused, equals: key)
              .onSubmit { if form.canConfirm { confirm() } }
              .frame(height: 28)
            }
          }
        }
      }
      .frame(height: fieldHeight)
      VStack(alignment: .leading, spacing: 4) {
        Text("Vorschau").font(.caption).foregroundStyle(.secondary)
        ScrollView {
          Text(form.preview)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .frame(height: 64)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
      }
      HStack {
        Text("Enter bestätigen · Esc abbrechen")
          .font(.caption).foregroundStyle(.secondary)
        Image(systemName: "info.circle")
          .foregroundStyle(.secondary)
          .help(
            "Jeder Parameter wird einmal abgefragt. Werte werden unverändert eingesetzt, nicht für die Shell maskiert. Atext führt keine Befehle aus; Zeilenumbrüche können im Terminal Befehle auslösen."
          )
        Spacer()
        Button("Abbrechen", action: cancel).keyboardShortcut(.cancelAction)
        Button(actionTitle, action: confirm)
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
          .disabled(!form.canConfirm)
      }
    }
    .padding(16)
    .frame(width: 620)
    .onAppear { focused = form.template.placeholders.first }
  }
}
