import Combine
import DexCore
import Foundation
import ServiceManagement

@MainActor
final class DexApplicationModel: ObservableObject {
  let store: ShortcutStore
  let monitor: GlobalShortcutMonitor
  let executor: ActionExecutor
  let history: ExecutionHistoryStore
  let windowDrill: WindowDrillModel

  @Published private(set) var launchAtLoginEnabled = false
  @Published private(set) var launchAtLoginError: String?
  @Published private(set) var isMenuBarItemVisible: Bool

  private var hasStarted = false

  init() {
    let store = ShortcutStore()
    let monitor = GlobalShortcutMonitor()
    let history = ExecutionHistoryStore()
    let executor = ActionExecutor(history: history)
    self.store = store
    self.monitor = monitor
    self.executor = executor
    self.history = history
    windowDrill = WindowDrillModel(shortcutStore: store)
    isMenuBarItemVisible = store.configuration.showsMenuBarItem

    store.onConfigurationChanged = { [weak self, weak monitor] configuration in
      monitor?.updateConfiguration(configuration)
      self?.isMenuBarItemVisible = configuration.showsMenuBarItem
    }
    monitor.onShortcut = { [weak executor] shortcut in
      executor?.execute(shortcut)
    }

    Task { @MainActor [weak self] in
      self?.startIfNeeded()
    }
  }

  func startIfNeeded() {
    guard !hasStarted else { return }
    hasStarted = true
    store.reload()
    monitor.updateConfiguration(store.configuration)
    monitor.start()
    launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
  }

  func execute(_ shortcut: DexShortcut) {
    executor.execute(shortcut)
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        if SMAppService.mainApp.status != .enabled {
          try SMAppService.mainApp.register()
        }
      } else if SMAppService.mainApp.status == .enabled {
        try SMAppService.mainApp.unregister()
      }
      launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
      launchAtLoginError = nil
      store.configuration.launchAtLogin = launchAtLoginEnabled
    } catch {
      launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
      launchAtLoginError = error.localizedDescription
    }
  }

  func setMenuBarItemVisible(_ visible: Bool) {
    guard isMenuBarItemVisible != visible else { return }
    isMenuBarItemVisible = visible
    store.configuration.showsMenuBarItem = visible
  }
}
