import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import DexCore
import Foundation

@MainActor
final class GlobalShortcutMonitor: ObservableObject {
  enum Status: Equatable {
    case stopped
    case active
    case permissionRequired
    case unavailable(String)

    var label: String {
      switch self {
      case .stopped: "Stopped"
      case .active: "Listening"
      case .permissionRequired: "Accessibility access required"
      case .unavailable(let message): message
      }
    }
  }

  @Published private(set) var status: Status = .stopped

  var onShortcut: ((DexShortcut) -> Void)?

  private var configuration = DexConfiguration()
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var triggerState = PhysicalTriggerState()
  private var suppressedKeyCodes: Set<UInt16> = []

  var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

  func updateConfiguration(_ configuration: DexConfiguration) {
    if self.configuration.trigger != configuration.trigger {
      triggerState.reset()
    }
    self.configuration = configuration
  }

  func start() {
    stop()
    guard hasAccessibilityPermission else {
      status = .permissionRequired
      return
    }

    let eventMask = eventMask(for: [.keyDown, .keyUp, .flagsChanged])
    let pointer = Unmanaged.passUnretained(self).toOpaque()
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: { _, type, event, userInfo in
          guard let userInfo else { return Unmanaged.passUnretained(event) }
          let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(userInfo).takeUnretainedValue()
          return monitor.handle(type: type, event: event)
        },
        userInfo: pointer
      )
    else {
      status = .unavailable("Input Monitoring access may be required")
      return
    }

    eventTap = tap
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    status = .active
  }

  func stop() {
    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
    }
    if let tap = eventTap {
      CGEvent.tapEnable(tap: tap, enable: false)
      CFMachPortInvalidate(tap)
    }
    runLoopSource = nil
    eventTap = nil
    triggerState.reset()
    suppressedKeyCodes.removeAll()
    if status == .active { status = .stopped }
  }

  func requestAccess() {
    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    _ = CGRequestListenEventAccess()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
      self?.start()
    }
  }

  func openPrivacySettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    else { return }
    NSWorkspace.shared.open(url)
  }

  private func eventMask(for types: [CGEventType]) -> CGEventMask {
    types.reduce(CGEventMask(0)) { partial, type in
      partial | (CGEventMask(1) << type.rawValue)
    }
  }

  private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
      triggerState.reset()
      suppressedKeyCodes.removeAll()
      return Unmanaged.passUnretained(event)
    }

    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

    if type == .flagsChanged {
      updateTriggerState(keyCode: keyCode, flags: event.flags)
      return Unmanaged.passUnretained(event)
    }

    if type == .keyUp, suppressedKeyCodes.remove(keyCode) != nil {
      return nil
    }

    guard type == .keyDown else { return Unmanaged.passUnretained(event) }
    let trigger = configuration.trigger
    guard triggerIsPressed(trigger) else {
      return Unmanaged.passUnretained(event)
    }

    let modifiers = activeAuxiliaryModifiers(for: event, trigger: trigger)
    guard
      let shortcut = configuration.shortcuts.first(where: {
        $0.isEnabled
          && $0.binding.keyCode == keyCode
          && $0.binding.effectiveModifiers(using: trigger) == modifiers
      })
    else {
      return Unmanaged.passUnretained(event)
    }

    suppressedKeyCodes.insert(keyCode)
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    if !isRepeat {
      DispatchQueue.main.async { [weak self] in
        self?.onShortcut?(shortcut)
      }
    }
    return nil
  }

  private func updateTriggerState(keyCode: UInt16, flags: CGEventFlags) {
    let trigger = configuration.trigger
    triggerState.update(
      keyCode: keyCode,
      familyIsActive: flags.contains(eventFlag(for: trigger)),
      trigger: trigger
    )
  }

  private func triggerIsPressed(_ trigger: TriggerKey) -> Bool {
    if triggerState.isPressed(trigger) { return true }

    // If Dex saw the other physical key in the same modifier family, do not
    // fall back to the generic flag and accidentally treat Left Command as
    // Right Command (or vice versa).
    if triggerState.hasTrackedKey(inFamilyOf: trigger) { return false }

    if CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(trigger.keyCode)) {
      return true
    }

    // The physical key-state query covers the uncommon case where Dex starts
    // while the trigger is already held. Never fall back to the generic event
    // flag: it cannot distinguish Left Command from Right Command.
    return false
  }

  private func activeAuxiliaryModifiers(
    for event: CGEvent,
    trigger: TriggerKey
  ) -> Set<AuxiliaryModifier> {
    var modifiers: Set<AuxiliaryModifier> = []

    for modifier in AuxiliaryModifier.allCases
    where modifier != trigger.correspondingModifier
      && event.flags.contains(eventFlag(for: modifier))
    {
      modifiers.insert(modifier)
    }
    return modifiers
  }

  private func eventFlag(for trigger: TriggerKey) -> CGEventFlags {
    switch trigger {
    case .rightCommand, .leftCommand: .maskCommand
    case .rightOption, .leftOption: .maskAlternate
    case .rightControl, .leftControl: .maskControl
    case .function: .maskSecondaryFn
    }
  }

  private func eventFlag(for modifier: AuxiliaryModifier) -> CGEventFlags {
    switch modifier {
    case .shift: .maskShift
    case .control: .maskControl
    case .option: .maskAlternate
    case .command: .maskCommand
    }
  }
}
