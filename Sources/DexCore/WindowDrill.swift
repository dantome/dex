import Foundation

public struct DrillRect: Equatable, Hashable, Sendable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  public func insetBy(dx: Double, dy: Double) -> DrillRect {
    DrillRect(
      x: x + dx,
      y: y + dy,
      width: max(0, width - (dx * 2)),
      height: max(0, height - (dy * 2))
    )
  }
}

public struct DrillDisplay: Identifiable, Equatable, Hashable, Sendable {
  public let id: String
  public let name: String
  /// The usable display bounds in the Accessibility API's top-left coordinate space.
  public let frame: DrillRect

  public init(id: String, name: String, frame: DrillRect) {
    self.id = id
    self.name = name
    self.frame = frame
  }
}

public struct DrillWindow: Identifiable, Equatable, Hashable, Sendable {
  public let id: String
  public let applicationName: String
  public let windowTitle: String
  public let bundleIdentifier: String?

  public init(
    id: String,
    applicationName: String,
    windowTitle: String,
    bundleIdentifier: String? = nil
  ) {
    self.id = id
    self.applicationName = applicationName
    self.windowTitle = windowTitle
    self.bundleIdentifier = bundleIdentifier
  }
}

public enum DrillZone: String, CaseIterable, Codable, Hashable, Sendable {
  case full
  case leftHalf
  case rightHalf
  case topHalf
  case bottomHalf
  case topLeft
  case topRight
  case bottomLeft
  case bottomRight
  case leftThird
  case middleThird
  case rightThird
  case leftTwoThirds
  case rightTwoThirds

  public var displayName: String {
    switch self {
    case .full: "Maximize"
    case .leftHalf: "Left half"
    case .rightHalf: "Right half"
    case .topHalf: "Top half"
    case .bottomHalf: "Bottom half"
    case .topLeft: "Top left"
    case .topRight: "Top right"
    case .bottomLeft: "Bottom left"
    case .bottomRight: "Bottom right"
    case .leftThird: "Left third"
    case .middleThird: "Middle third"
    case .rightThird: "Right third"
    case .leftTwoThirds: "Left two thirds"
    case .rightTwoThirds: "Right two thirds"
    }
  }

  public var layoutFamily: DrillLayoutFamily {
    switch self {
    case .full:
      .fullScreen
    case .leftHalf, .rightHalf, .topHalf, .bottomHalf:
      .halves
    case .topLeft, .topRight, .bottomLeft, .bottomRight:
      .quarters
    case .leftThird, .middleThird, .rightThird:
      .thirds
    case .leftTwoThirds, .rightTwoThirds:
      .twoThirds
    }
  }

  public var normalizedFrame: DrillRect {
    switch self {
    case .full: DrillRect(x: 0, y: 0, width: 1, height: 1)
    case .leftHalf: DrillRect(x: 0, y: 0, width: 0.5, height: 1)
    case .rightHalf: DrillRect(x: 0.5, y: 0, width: 0.5, height: 1)
    case .topHalf: DrillRect(x: 0, y: 0, width: 1, height: 0.5)
    case .bottomHalf: DrillRect(x: 0, y: 0.5, width: 1, height: 0.5)
    case .topLeft: DrillRect(x: 0, y: 0, width: 0.5, height: 0.5)
    case .topRight: DrillRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
    case .bottomLeft: DrillRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
    case .bottomRight: DrillRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
    case .leftThird: DrillRect(x: 0, y: 0, width: 1.0 / 3.0, height: 1)
    case .middleThird: DrillRect(x: 1.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1)
    case .rightThird: DrillRect(x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1)
    case .leftTwoThirds: DrillRect(x: 0, y: 0, width: 2.0 / 3.0, height: 1)
    case .rightTwoThirds: DrillRect(x: 1.0 / 3.0, y: 0, width: 2.0 / 3.0, height: 1)
    }
  }

  public func frame(in display: DrillDisplay) -> DrillRect {
    let unit = normalizedFrame
    return DrillRect(
      x: display.frame.x + (display.frame.width * unit.x),
      y: display.frame.y + (display.frame.height * unit.y),
      width: display.frame.width * unit.width,
      height: display.frame.height * unit.height
    )
  }
}

public enum DrillLayoutFamily: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
  case fullScreen
  case halves
  case thirds
  case twoThirds
  case quarters

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .fullScreen: "Full screen"
    case .halves: "Halves"
    case .thirds: "Thirds"
    case .twoThirds: "Two-thirds"
    case .quarters: "Quarters"
    }
  }
}

public struct DrillAssignment: Identifiable, Equatable, Hashable, Sendable {
  public let window: DrillWindow
  public let displayID: String
  public let zone: DrillZone

  public var id: String { window.id }

  public init(window: DrillWindow, displayID: String, zone: DrillZone) {
    self.window = window
    self.displayID = displayID
    self.zone = zone
  }
}

public struct DrillRound: Identifiable, Equatable, Hashable, Sendable {
  public let id: UUID
  public let assignments: [DrillAssignment]

  public init(id: UUID = UUID(), assignments: [DrillAssignment]) {
    self.id = id
    self.assignments = assignments
  }
}

public enum WindowDrillGeometry {
  public static func matches(
    actual: DrillRect,
    target: DrillRect,
    tolerance: Double = 18
  ) -> Bool {
    abs(actual.x - target.x) <= tolerance
      && abs(actual.y - target.y) <= tolerance
      && abs(actual.width - target.width) <= tolerance
      && abs(actual.height - target.height) <= tolerance
  }

  /// Matches a real application window against a Magnet target using a
  /// display-relative tolerance. AppKit title bars, terminal cell increments,
  /// window gaps, and backing-scale rounding can all make a correctly tiled
  /// window differ by more than a fixed number of points on large displays.
  public static func matchesWindow(
    actual: DrillRect,
    target: DrillRect,
    on display: DrillDisplay,
    toleranceFraction: Double = 0.07,
    minimumTolerance: Double = 18
  ) -> Bool {
    let horizontalTolerance = max(minimumTolerance, display.frame.width * toleranceFraction)
    let verticalTolerance = max(minimumTolerance, display.frame.height * toleranceFraction)
    return abs(actual.x - target.x) <= horizontalTolerance
      && abs(actual.y - target.y) <= verticalTolerance
      && abs(actual.width - target.width) <= horizontalTolerance
      && abs(actual.height - target.height) <= verticalTolerance
  }

  /// Matches a Magnet placement when an application's minimum window size
  /// prevents it from reaching the exact target. Magnet keeps the window
  /// anchored to the requested screen edge in this case, so accept a bounded
  /// expansion from that edge without letting a maximized window satisfy a
  /// half, third, or quarter target.
  public static func matchesWindow(
    actual: DrillRect,
    target: DrillRect,
    for zone: DrillZone,
    on display: DrillDisplay,
    toleranceFraction: Double = 0.07,
    minimumTolerance: Double = 18,
    maximumOverflowFraction: Double = 0.30
  ) -> Bool {
    if matchesWindow(
      actual: actual,
      target: target,
      on: display,
      toleranceFraction: toleranceFraction,
      minimumTolerance: minimumTolerance
    ) {
      return true
    }

    // Geometry alone cannot prove that an oversized result came from an
    // application's minimum size. If it cleanly matches another Magnet zone,
    // treat it as that zone instead of accepting it through the fallback. This
    // is especially important for distinguishing halves from thirds.
    let matchesAnotherZone = DrillZone.allCases.lazy
      .filter { $0 != zone }
      .contains { otherZone in
        matchesWindow(
          actual: actual,
          target: otherZone.frame(in: display),
          on: display,
          toleranceFraction: toleranceFraction,
          minimumTolerance: minimumTolerance
        )
      }
    guard !matchesAnotherZone else { return false }

    let horizontalTolerance = max(minimumTolerance, display.frame.width * toleranceFraction)
    let verticalTolerance = max(minimumTolerance, display.frame.height * toleranceFraction)
    let horizontalOverflow = display.frame.width * maximumOverflowFraction
    let verticalOverflow = display.frame.height * maximumOverflowFraction

    guard
      actual.width >= target.width - horizontalTolerance,
      actual.height >= target.height - verticalTolerance,
      actual.width <= target.width + horizontalOverflow,
      actual.height <= target.height + verticalOverflow
    else { return false }

    let unit = zone.normalizedFrame
    return matchesAxis(
      actualMinimum: actual.x,
      actualMaximum: actual.x + actual.width,
      targetMinimum: target.x,
      targetMaximum: target.x + target.width,
      normalizedMinimum: unit.x,
      normalizedLength: unit.width,
      tolerance: horizontalTolerance
    ) && matchesAxis(
      actualMinimum: actual.y,
      actualMaximum: actual.y + actual.height,
      targetMinimum: target.y,
      targetMaximum: target.y + target.height,
      normalizedMinimum: unit.y,
      normalizedLength: unit.height,
      tolerance: verticalTolerance
    )
  }

  private static func matchesAxis(
    actualMinimum: Double,
    actualMaximum: Double,
    targetMinimum: Double,
    targetMaximum: Double,
    normalizedMinimum: Double,
    normalizedLength: Double,
    tolerance: Double
  ) -> Bool {
    let normalizedMaximum = normalizedMinimum + normalizedLength
    if abs(normalizedLength - 1) < 0.0001 {
      return abs(actualMinimum - targetMinimum) <= tolerance
        && abs(actualMaximum - targetMaximum) <= tolerance
    }
    if abs(normalizedMinimum) < 0.0001 {
      return abs(actualMinimum - targetMinimum) <= tolerance
    }
    if abs(normalizedMaximum - 1) < 0.0001 {
      return abs(actualMaximum - targetMaximum) <= tolerance
    }
    let actualCenter = (actualMinimum + actualMaximum) / 2
    let targetCenter = (targetMinimum + targetMaximum) / 2
    return abs(actualCenter - targetCenter) <= tolerance
  }

  /// Returns true when macOS reports the same physical display topology, even
  /// if it delivers the displays in a different order or introduces sub-pixel
  /// rounding noise in their usable frames.
  public static func sameDisplayTopology(
    _ lhs: [DrillDisplay],
    _ rhs: [DrillDisplay],
    tolerance: Double = 1
  ) -> Bool {
    guard lhs.count == rhs.count else { return false }
    let rhsByID = Dictionary(uniqueKeysWithValues: rhs.map { ($0.id, $0) })
    return lhs.allSatisfy { display in
      guard let other = rhsByID[display.id] else { return false }
      return matches(actual: display.frame, target: other.frame, tolerance: tolerance)
    }
  }
}

public enum WindowDrillGenerator {
  public static func generate<R: RandomNumberGenerator>(
    windows: [DrillWindow],
    displays: [DrillDisplay],
    roundCount: Int,
    enabledFamilies: Set<DrillLayoutFamily> = Set(DrillLayoutFamily.allCases),
    using generator: inout R
  ) -> [DrillRound] {
    guard
      !windows.isEmpty,
      !displays.isEmpty,
      roundCount > 0,
      !enabledFamilies.isEmpty
    else { return [] }

    let usableWindows = Array(windows.prefix(displays.count * 4))
    let feasibleWindowCounts = (1...usableWindows.count).filter { windowCount in
      !feasibleDisplayCounts(
        windowCount: windowCount,
        displayCount: displays.count,
        enabledFamilies: enabledFamilies
      ).isEmpty
    }
    guard !feasibleWindowCounts.isEmpty else { return [] }
    var rounds: [DrillRound] = []
    var remainingWindowCounts: [Int] = []
    var previousSignature: String?

    for _ in 0..<roundCount {
      if remainingWindowCounts.isEmpty {
        remainingWindowCounts = feasibleWindowCounts.shuffled(using: &generator)
      }
      let activeWindowCount = remainingWindowCounts.removeLast()
      let feasibleDisplayCounts = feasibleDisplayCounts(
        windowCount: activeWindowCount,
        displayCount: displays.count,
        enabledFamilies: enabledFamilies
      )
      var candidate = makeRound(
        windows: usableWindows,
        activeWindowCount: activeWindowCount,
        displays: displays,
        feasibleDisplayCounts: feasibleDisplayCounts,
        enabledFamilies: enabledFamilies,
        using: &generator
      )
      var attempts = 0
      while candidate.signature == previousSignature && attempts < 6 {
        candidate = makeRound(
          windows: usableWindows,
          activeWindowCount: activeWindowCount,
          displays: displays,
          feasibleDisplayCounts: feasibleDisplayCounts,
          enabledFamilies: enabledFamilies,
          using: &generator
        )
        attempts += 1
      }
      rounds.append(candidate)
      previousSignature = candidate.signature
    }
    return rounds
  }

  private static func makeRound<R: RandomNumberGenerator>(
    windows: [DrillWindow],
    activeWindowCount: Int,
    displays: [DrillDisplay],
    feasibleDisplayCounts: [Int],
    enabledFamilies: Set<DrillLayoutFamily>,
    using generator: inout R
  ) -> DrillRound {
    let activeWindows = windows.shuffled(using: &generator).prefix(activeWindowCount)
    let activeDisplayCount = feasibleDisplayCounts.randomElement(using: &generator)
      ?? feasibleDisplayCounts[0]
    let activeDisplays = Array(displays.shuffled(using: &generator).prefix(activeDisplayCount))

    var groups = Array(repeating: [DrillWindow](), count: activeDisplayCount)
    for (index, window) in activeWindows.enumerated() {
      groups[index % activeDisplayCount].append(window)
    }

    var assignments: [DrillAssignment] = []
    for (index, group) in groups.enumerated() {
      let zones = layout(
        for: group.count,
        enabledFamilies: enabledFamilies,
        using: &generator
      )
      for (window, zone) in zip(group, zones) {
        assignments.append(
          DrillAssignment(window: window, displayID: activeDisplays[index].id, zone: zone)
        )
      }
    }
    return DrillRound(assignments: assignments.shuffled(using: &generator))
  }

  private static func layout<R: RandomNumberGenerator>(
    for count: Int,
    enabledFamilies: Set<DrillLayoutFamily>,
    using generator: inout R
  ) -> [DrillZone] {
    let layouts = layouts(for: count).filter { zones in
      Set(zones.map(\.layoutFamily)).isSubset(of: enabledFamilies)
    }
    return layouts.randomElement(using: &generator) ?? layouts[0]
  }

  public static func canGenerate(
    windowCount: Int,
    displayCount: Int,
    enabledFamilies: Set<DrillLayoutFamily>
  ) -> Bool {
    guard windowCount > 0, displayCount > 0 else { return false }
    let usableWindowCount = min(windowCount, displayCount * 4)
    return (1...usableWindowCount).contains { activeWindowCount in
      !feasibleDisplayCounts(
        windowCount: activeWindowCount,
        displayCount: displayCount,
        enabledFamilies: enabledFamilies
      ).isEmpty
    }
  }

  private static func feasibleDisplayCounts(
    windowCount: Int,
    displayCount: Int,
    enabledFamilies: Set<DrillLayoutFamily>
  ) -> [Int] {
    guard windowCount > 0, displayCount > 0 else { return [] }
    return (1...min(windowCount, displayCount)).filter { activeDisplayCount in
      let baseGroupSize = windowCount / activeDisplayCount
      let largerGroupCount = windowCount % activeDisplayCount
      let groupSizes = (0..<activeDisplayCount).map { index in
        baseGroupSize + (index < largerGroupCount ? 1 : 0)
      }
      return groupSizes.allSatisfy { count in
        layouts(for: count).contains { zones in
          Set(zones.map(\.layoutFamily)).isSubset(of: enabledFamilies)
        }
      }
    }
  }

  private static func layouts(for count: Int) -> [[DrillZone]] {
    switch count {
    case 1:
      [[.full]]
    case 2:
      [
        [.leftHalf, .rightHalf],
        [.topHalf, .bottomHalf],
        [.leftThird, .rightTwoThirds],
        [.leftTwoThirds, .rightThird],
      ]
    case 3:
      [
        [.leftThird, .middleThird, .rightThird],
        [.leftHalf, .topRight, .bottomRight],
        [.topLeft, .bottomLeft, .rightHalf],
      ]
    case 4:
      [[.topLeft, .topRight, .bottomLeft, .bottomRight]]
    default:
      []
    }
  }
}

private extension DrillRound {
  var signature: String {
    assignments
      .sorted { $0.window.id < $1.window.id }
      .map { "\($0.window.id):\($0.displayID):\($0.zone.rawValue)" }
      .joined(separator: "|")
  }
}
