import AppKit

/// User-selectable color scheme. `.system` follows the macOS setting.
enum AppearanceMode: String, CaseIterable, Identifiable {
  case system, light, dark

  static let defaultsKey = "appearanceMode"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .system: return "Wie System"
    case .light: return "Hell"
    case .dark: return "Dunkel"
    }
  }

  var symbolName: String {
    switch self {
    case .system: return "circle.lefthalf.filled"
    case .light: return "sun.max"
    case .dark: return "moon"
    }
  }

  /// `nil` lets AppKit follow the system appearance.
  var nsAppearance: NSAppearance? {
    switch self {
    case .system: return nil
    case .light: return NSAppearance(named: .aqua)
    case .dark: return NSAppearance(named: .darkAqua)
    }
  }

  static func stored(in defaults: UserDefaults = .standard) -> AppearanceMode {
    defaults.string(forKey: defaultsKey).flatMap(AppearanceMode.init(rawValue:)) ?? .system
  }

  func apply(to application: NSApplication = .shared) {
    application.appearance = nsAppearance
  }
}
