import Foundation

/// Tracks the physical left/right key used by a Dex trigger.
///
/// Modifier events include both the physical key code and a generic family
/// flag. Combining them lets Dex distinguish Right Command from Left Command
/// without querying global key state before macOS has applied the event.
public struct PhysicalTriggerState: Equatable, Sendable {
  public private(set) var pressedKeyCodes: Set<UInt16> = []

  public init() {}

  public mutating func reset() {
    pressedKeyCodes.removeAll()
  }

  public mutating func update(
    keyCode: UInt16,
    familyIsActive: Bool,
    trigger: TriggerKey
  ) {
    guard trigger.familyKeyCodes.contains(keyCode) else { return }

    if !familyIsActive {
      pressedKeyCodes.subtract(trigger.familyKeyCodes)
    } else if pressedKeyCodes.contains(keyCode) {
      // One side was released while the other side in the family remains down.
      pressedKeyCodes.remove(keyCode)
    } else {
      pressedKeyCodes.insert(keyCode)
    }
  }

  public func isPressed(_ trigger: TriggerKey) -> Bool {
    pressedKeyCodes.contains(trigger.keyCode)
  }

  public func hasTrackedKey(inFamilyOf trigger: TriggerKey) -> Bool {
    !pressedKeyCodes.isDisjoint(with: trigger.familyKeyCodes)
  }
}
