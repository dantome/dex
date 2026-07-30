import AppKit
import ApplicationServices

@MainActor
final class ApplicationWindowCycler {
  private static let continuationInterval: TimeInterval = 2.5

  private struct CycleState {
    let processIdentifier: pid_t
    var windows: [AXUIElement]
    var selectedWindow: AXUIElement
    var lastInvocationUptime: TimeInterval
  }

  private var cycleState: CycleState?

  /// Activates one of the application's existing windows. When the app is
  /// already active, the window after its focused window is selected so that
  /// repeated shortcut presses cycle through all of the app's windows.
  func activateNextWindow(in application: NSRunningApplication) -> Bool {
    guard AXIsProcessTrusted() else { return false }

    let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
    guard
      let allWindows: [AXUIElement] = attribute(
        kAXWindowsAttribute,
        of: applicationElement
      )
    else {
      return false
    }

    let currentWindows = allWindows.filter(isStandardWindow)
    guard !currentWindows.isEmpty else { return false }

    let invocationUptime = ProcessInfo.processInfo.systemUptime
    let applicationWasActive = application.isActive
    let focusedWindow: AXUIElement? = attribute(
      kAXFocusedWindowAttribute,
      of: applicationElement
    )
    let windows: [AXUIElement]
    let targetWindow: AXUIElement
    if
      let state = reconciledCycleState(
        for: application.processIdentifier,
        currentWindows: currentWindows
      ),
      invocationUptime - state.lastInvocationUptime <= Self.continuationInterval,
      let selectedIndex = state.windows.firstIndex(where: {
        CFEqual($0, state.selectedWindow)
      })
    {
      windows = state.windows
      targetWindow = windows[(selectedIndex + 1) % windows.count]
    } else {
      windows = currentWindows
      let focusedIndex = focusedWindow.flatMap { focusedWindow in
        windows.firstIndex { CFEqual($0, focusedWindow) }
      }
      if applicationWasActive, let focusedIndex {
        targetWindow = windows[(focusedIndex + 1) % windows.count]
      } else {
        // On the first press, retain the app's current front window. Later
        // presses advance through this snapshot even if macOS changes z-order.
        targetWindow = windows[focusedIndex ?? 0]
      }
    }

    cycleState = CycleState(
      processIdentifier: application.processIdentifier,
      windows: windows,
      selectedWindow: targetWindow,
      lastInvocationUptime: invocationUptime
    )

    _ = application.activate()
    AXUIElementSetAttributeValue(
      targetWindow,
      kAXMinimizedAttribute as CFString,
      kCFBooleanFalse
    )
    AXUIElementSetAttributeValue(
      targetWindow,
      kAXMainAttribute as CFString,
      kCFBooleanTrue
    )
    AXUIElementSetAttributeValue(
      targetWindow,
      kAXFocusedAttribute as CFString,
      kCFBooleanTrue
    )

    return AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString) == .success
  }

  private func reconciledCycleState(
    for processIdentifier: pid_t,
    currentWindows: [AXUIElement]
  ) -> CycleState? {
    guard var state = cycleState, state.processIdentifier == processIdentifier else {
      return nil
    }

    state.windows.removeAll { savedWindow in
      !currentWindows.contains { CFEqual($0, savedWindow) }
    }
    for window in currentWindows
    where !state.windows.contains(where: { CFEqual($0, window) }) {
      state.windows.append(window)
    }
    guard
      !state.windows.isEmpty,
      state.windows.contains(where: { CFEqual($0, state.selectedWindow) })
    else {
      return nil
    }
    return state
  }

  private func isStandardWindow(_ window: AXUIElement) -> Bool {
    let role: String? = attribute(kAXRoleAttribute, of: window)
    guard role == kAXWindowRole else { return false }

    // Some applications do not expose a subrole. Keep those windows, while
    // excluding sheets, dialogs, and other transient UI when a subrole exists.
    let subrole: String? = attribute(kAXSubroleAttribute, of: window)
    return subrole == nil || subrole == kAXStandardWindowSubrole
  }

  private func attribute<Value>(_ name: String, of element: AXUIElement) -> Value? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
    else {
      return nil
    }
    return value as? Value
  }
}
