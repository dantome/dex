import AppKit
import DexCore
import SwiftUI

private final class DexAppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

    let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
    let existingInstance =
      NSRunningApplication
      .runningApplications(withBundleIdentifier: bundleIdentifier)
      .first { $0.processIdentifier != currentProcessIdentifier && !$0.isTerminated }

    guard let existingInstance else { return }
    existingInstance.activate()
    NSApplication.shared.terminate(nil)
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    guard !flag else { return true }

    sender.activate(ignoringOtherApps: true)
    let openedSettings = sender.sendAction(
      Selector(("showSettingsWindow:")),
      to: nil,
      from: nil
    )
    if !openedSettings {
      sender.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      sender.windows
        .first(where: { $0.isVisible && $0.canBecomeKey && $0.styleMask.contains(.titled) })?
        .makeKeyAndOrderFront(nil)
    }
    return true
  }
}

@main
struct DexApp: App {
  @NSApplicationDelegateAdaptor(DexAppDelegate.self) private var appDelegate
  @StateObject private var model = DexApplicationModel()

  var body: some Scene {
    MenuBarExtra(isInserted: menuBarItemBinding) {
      MenuBarContentView(model: model)
    } label: {
      DexLogoMark()
    }
    .menuBarExtraStyle(.menu)

    Settings {
      DexSettingsView(model: model)
    }
  }

  private var menuBarItemBinding: Binding<Bool> {
    Binding(
      get: { model.isMenuBarItemVisible },
      set: { model.setMenuBarItemVisible($0) }
    )
  }
}

private struct MenuBarContentView: View {
  @Environment(\.openSettings) private var openSettings
  @ObservedObject private var store: ShortcutStore
  @ObservedObject private var monitor: GlobalShortcutMonitor
  @ObservedObject private var executor: ActionExecutor
  private let model: DexApplicationModel

  init(model: DexApplicationModel) {
    self.model = model
    _store = ObservedObject(wrappedValue: model.store)
    _monitor = ObservedObject(wrappedValue: model.monitor)
    _executor = ObservedObject(wrappedValue: model.executor)
  }

  var body: some View {
    let shortcuts = store.configuration.shortcuts.filter(\.isEnabled)

    Group {
      if shortcuts.isEmpty {
        Text("No shortcuts yet")
      } else {
        ForEach(shortcuts) { shortcut in
          ShortcutMenuButton(
            shortcut: shortcut,
            trigger: store.configuration.trigger
          ) {
            model.execute(shortcut)
          }
        }
      }

      Divider()

      if monitor.status != .active {
        Button("Enable Global Shortcuts…") {
          monitor.requestAccess()
        }
      } else {
        Label("Global shortcuts active", systemImage: "checkmark.circle")
      }

      Button {
        presentSettings()
      } label: {
        Label("Settings…", systemImage: "gearshape")
      }
      .keyboardShortcut(",", modifiers: .command)

      if let result = executor.lastResult {
        Divider()
        Text(result)
      }

      Divider()
      Button("Quit Dex") {
        NSApplication.shared.terminate(nil)
      }
    }
    .onAppear {
      model.startIfNeeded()
      store.reload()
    }
  }

  private func presentSettings() {
    NSApplication.shared.activate(ignoringOtherApps: true)
    openSettings()

    // Opening a Settings scene from an LSUIElement menu-bar app does not
    // consistently make the scene key. Give SwiftUI a run-loop turn to create
    // the window, then explicitly bring the titled settings window forward.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      NSApplication.shared.activate(ignoringOtherApps: true)
      NSApplication.shared.windows
        .first(where: { window in
          window.isVisible && window.canBecomeKey && window.styleMask.contains(.titled)
        })?
        .makeKeyAndOrderFront(nil)
    }
  }
}

private struct ShortcutMenuButton: View {
  let shortcut: DexShortcut
  let trigger: TriggerKey
  let action: () -> Void

  @ViewBuilder
  var body: some View {
    if let keyboardShortcut = shortcut.binding.menuKeyboardShortcut(using: trigger) {
      Button(shortcut.name, action: action)
        .keyboardShortcut(keyboardShortcut)
    } else {
      // Fn is reserved by macOS and cannot be represented as a native menu
      // keyboard equivalent. Keep its full shortcut visible in the title.
      Button(
        "\(shortcut.name) — \(shortcut.binding.display(using: trigger))",
        action: action
      )
    }
  }
}

extension KeyBinding {
  fileprivate func menuKeyboardShortcut(using trigger: TriggerKey) -> KeyboardShortcut? {
    guard trigger != .function, let keyEquivalent = menuKeyEquivalent else { return nil }

    var eventModifiers: EventModifiers = []
    switch trigger.correspondingModifier {
    case .command: eventModifiers.insert(.command)
    case .option: eventModifiers.insert(.option)
    case .control: eventModifiers.insert(.control)
    case .shift: eventModifiers.insert(.shift)
    case nil: break
    }

    for modifier in effectiveModifiers(using: trigger) {
      switch modifier {
      case .command: eventModifiers.insert(.command)
      case .option: eventModifiers.insert(.option)
      case .control: eventModifiers.insert(.control)
      case .shift: eventModifiers.insert(.shift)
      }
    }

    return KeyboardShortcut(keyEquivalent, modifiers: eventModifiers)
  }

  fileprivate var menuKeyEquivalent: KeyEquivalent? {
    switch keyCode {
    case 36: return .return
    case 48: return .tab
    case 49: return .space
    case 51: return .delete
    case 53: return .escape
    case 123: return .leftArrow
    case 124: return .rightArrow
    case 125: return .downArrow
    case 126: return .upArrow
    default:
      if keyLabel.hasPrefix("F"),
        let number = Int(keyLabel.dropFirst()),
        (1...12).contains(number),
        let scalar = UnicodeScalar(0xF704 + number - 1)
      {
        return KeyEquivalent(Character(scalar))
      }

      guard keyLabel.count == 1, let character = keyLabel.lowercased().first else {
        return nil
      }
      return KeyEquivalent(character)
    }
  }
}
