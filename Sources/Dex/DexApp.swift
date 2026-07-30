import AppKit
import DexCore
import SwiftUI

@MainActor
private final class DexAppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

    let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
    let existingInstance =
      NSRunningApplication
      .runningApplications(withBundleIdentifier: bundleIdentifier)
      .first { $0.processIdentifier != currentProcessIdentifier && !$0.isTerminated }

    if let existingInstance {
      existingInstance.activate()
      NSApplication.shared.terminate(nil)
    }
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    guard !flag else { return true }

    presentSettings()
    return true
  }

  private func presentSettings() {
    DexSettingsPresenter.shared.present()
  }
}

@main
struct DexApp: App {
  @NSApplicationDelegateAdaptor(DexAppDelegate.self) private var appDelegate
  @StateObject private var model: DexApplicationModel
  @StateObject private var menuBarController: DexMenuBarController

  init() {
    let model = DexApplicationModel()
    _model = StateObject(wrappedValue: model)
    _menuBarController = StateObject(
      wrappedValue: DexMenuBarController(model: model)
    )
  }

  var body: some Scene {
    Settings {
      DexSettingsView(model: model)
    }
      .commands {
        WindowDrillCommands()
      }
    // Accessing the StateObject from the scene body keeps the AppKit status
    // item alive even when Dex has no visible windows.
    let _ = menuBarController
  }
}
