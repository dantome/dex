import DexCore
import XCTest

final class WindowDrillTests: XCTestCase {
  func testEveryRoundUsesUniqueWindowsFromSelectedPool() {
    let windows = (1...7).map {
      DrillWindow(id: "window-\($0)", applicationName: "App \($0)", windowTitle: "Window")
    }
    let displays = (1...3).map {
      DrillDisplay(
        id: "display-\($0)",
        name: "Display \($0)",
        frame: DrillRect(x: Double(($0 - 1) * 1000), y: 0, width: 1000, height: 800)
      )
    }
    var random = SeededGenerator(seed: 42)

    let rounds = WindowDrillGenerator.generate(
      windows: windows,
      displays: displays,
      roundCount: 25,
      using: &random
    )

    XCTAssertEqual(rounds.count, 25)
    for round in rounds {
      let assignedWindowIDs = round.assignments.map(\.window.id)
      XCTAssertEqual(Set(assignedWindowIDs).count, assignedWindowIDs.count)
      XCTAssertTrue(Set(assignedWindowIDs).isSubset(of: Set(windows.map(\.id))))
      XCTAssertTrue((1...windows.count).contains(assignedWindowIDs.count))
      XCTAssertTrue(round.assignments.allSatisfy { assignment in
        displays.contains { $0.id == assignment.displayID }
      })
    }
  }

  func testThreeSelectedWindowsProduceOneTwoAndThreeWindowRounds() {
    let windows = (1...3).map {
      DrillWindow(id: "window-\($0)", applicationName: "App", windowTitle: "\($0)")
    }
    let display = DrillDisplay(
      id: "display",
      name: "Display",
      frame: DrillRect(x: 0, y: 0, width: 1200, height: 900)
    )
    var random = SeededGenerator(seed: 27)

    let rounds = WindowDrillGenerator.generate(
      windows: windows,
      displays: [display],
      roundCount: 3,
      using: &random
    )

    XCTAssertEqual(Set(rounds.map { $0.assignments.count }), [1, 2, 3])
  }

  func testOneDisplayThreeWindowRoundsUseCompleteNonOverlappingLayouts() {
    let windows = (1...3).map {
      DrillWindow(id: "window-\($0)", applicationName: "App", windowTitle: "\($0)")
    }
    let display = DrillDisplay(
      id: "display",
      name: "Display",
      frame: DrillRect(x: 0, y: 0, width: 1200, height: 900)
    )
    var random = SeededGenerator(seed: 7)

    let rounds = WindowDrillGenerator.generate(
      windows: windows,
      displays: [display],
      roundCount: 20,
      using: &random
    )

    for round in rounds {
      let frames = round.assignments.map { $0.zone.normalizedFrame }
      let area = frames.reduce(0.0) { $0 + ($1.width * $1.height) }
      XCTAssertEqual(area, 1, accuracy: 0.0001)
      for firstIndex in frames.indices {
        for secondIndex in frames.indices where secondIndex > firstIndex {
          XCTAssertFalse(hasPositiveIntersection(frames[firstIndex], frames[secondIndex]))
        }
      }
    }
  }

  func testGeneratorLimitsWindowsToFourPerDisplay() {
    let windows = (1...8).map {
      DrillWindow(id: "window-\($0)", applicationName: "App", windowTitle: "\($0)")
    }
    let displays = [
      DrillDisplay(id: "left", name: "Left", frame: DrillRect(x: 0, y: 0, width: 800, height: 600)),
      DrillDisplay(id: "right", name: "Right", frame: DrillRect(x: 800, y: 0, width: 800, height: 600)),
    ]
    var random = SeededGenerator(seed: 99)

    let rounds = WindowDrillGenerator.generate(
      windows: windows,
      displays: displays,
      roundCount: 10,
      using: &random
    )

    for round in rounds {
      let counts = Dictionary(grouping: round.assignments, by: \.displayID).mapValues(\.count)
      XCTAssertTrue(counts.values.allSatisfy { $0 <= 4 })
    }
  }

  func testGeneratorHonorsDisabledQuarterLayouts() {
    let windows = (1...4).map {
      DrillWindow(id: "window-\($0)", applicationName: "App", windowTitle: "\($0)")
    }
    let displays = [
      DrillDisplay(id: "left", name: "Left", frame: DrillRect(x: 0, y: 0, width: 800, height: 600)),
      DrillDisplay(id: "right", name: "Right", frame: DrillRect(x: 800, y: 0, width: 800, height: 600)),
    ]
    var random = SeededGenerator(seed: 12)

    let rounds = WindowDrillGenerator.generate(
      windows: windows,
      displays: displays,
      roundCount: 20,
      enabledFamilies: [.fullScreen, .halves, .thirds, .twoThirds],
      using: &random
    )

    XCTAssertEqual(rounds.count, 20)
    XCTAssertTrue(
      rounds.flatMap(\.assignments).allSatisfy { $0.zone.layoutFamily != .quarters }
    )
  }

  func testGeneratorCanRequireQuartersAndUseSmallerCompatibleSubsets() {
    let windows = (1...4).map {
      DrillWindow(id: "window-\($0)", applicationName: "App", windowTitle: "\($0)")
    }
    let display = DrillDisplay(
      id: "display",
      name: "Display",
      frame: DrillRect(x: 0, y: 0, width: 1200, height: 900)
    )
    var random = SeededGenerator(seed: 22)

    let rounds = WindowDrillGenerator.generate(
      windows: windows,
      displays: [display],
      roundCount: 5,
      enabledFamilies: [.quarters],
      using: &random
    )

    XCTAssertEqual(rounds.count, 5)
    XCTAssertTrue(
      rounds.flatMap(\.assignments).allSatisfy { $0.zone.layoutFamily == .quarters }
    )
    XCTAssertTrue(
      WindowDrillGenerator.canGenerate(
        windowCount: 4,
        displayCount: 1,
        enabledFamilies: [.fullScreen]
      )
    )
    XCTAssertFalse(
      WindowDrillGenerator.canGenerate(
        windowCount: 3,
        displayCount: 1,
        enabledFamilies: [.quarters]
      )
    )
  }

  func testGeometryAllowsSmallMagnetRoundingDifferences() {
    let target = DrillRect(x: 0, y: 25, width: 756, height: 924)
    XCTAssertTrue(
      WindowDrillGeometry.matches(
        actual: DrillRect(x: 3, y: 27, width: 750, height: 920),
        target: target
      )
    )
    XCTAssertFalse(
      WindowDrillGeometry.matches(
        actual: DrillRect(x: 50, y: 25, width: 706, height: 924),
        target: target
      )
    )
  }

  func testWindowMatchingAcceptsRealisticQuarterLayoutDifferences() {
    let display = DrillDisplay(
      id: "main",
      name: "Built-in",
      frame: DrillRect(x: 0, y: 25, width: 1512, height: 924)
    )
    let target = DrillZone.bottomRight.frame(in: display)

    XCTAssertTrue(
      WindowDrillGeometry.matchesWindow(
        actual: DrillRect(x: 770, y: 500, width: 730, height: 430),
        target: target,
        on: display
      )
    )
  }

  func testWindowMatchingRejectsWrongQuarterAndMateriallyWrongSize() {
    let display = DrillDisplay(
      id: "main",
      name: "Built-in",
      frame: DrillRect(x: 0, y: 25, width: 1512, height: 924)
    )
    let bottomRight = DrillZone.bottomRight.frame(in: display)

    XCTAssertFalse(
      WindowDrillGeometry.matchesWindow(
        actual: DrillZone.topRight.frame(in: display),
        target: bottomRight,
        on: display
      )
    )
    XCTAssertFalse(
      WindowDrillGeometry.matchesWindow(
        actual: DrillRect(x: 760, y: 490, width: 580, height: 300),
        target: bottomRight,
        on: display
      )
    )
  }

  func testWindowMatchingAcceptsBottomHalfClampedToApplicationMinimumHeight() {
    // Mirrors the Built-in display and ChatGPT frame from the regression screenshot.
    let display = DrillDisplay(
      id: "main",
      name: "Built-in",
      frame: DrillRect(x: 0, y: 33, width: 1512, height: 949)
    )
    let target = DrillZone.bottomHalf.frame(in: display)

    XCTAssertTrue(
      WindowDrillGeometry.matchesWindow(
        actual: DrillRect(x: 0, y: 247, width: 1512, height: 735),
        target: target,
        for: .bottomHalf,
        on: display
      )
    )
  }

  func testMinimumSizeMatchingDoesNotAcceptMaximizedWindowAsBottomHalf() {
    let display = DrillDisplay(
      id: "main",
      name: "Built-in",
      frame: DrillRect(x: 0, y: 33, width: 1512, height: 949)
    )
    let target = DrillZone.bottomHalf.frame(in: display)

    XCTAssertFalse(
      WindowDrillGeometry.matchesWindow(
        actual: display.frame,
        target: target,
        for: .bottomHalf,
        on: display
      )
    )
  }

  func testMinimumSizeMatchingRequiresTheRequestedEdgeAnchor() {
    let display = DrillDisplay(
      id: "main",
      name: "Built-in",
      frame: DrillRect(x: 0, y: 33, width: 1512, height: 949)
    )
    let target = DrillZone.bottomHalf.frame(in: display)

    XCTAssertFalse(
      WindowDrillGeometry.matchesWindow(
        actual: DrillRect(x: 0, y: 150, width: 1512, height: 735),
        target: target,
        for: .bottomHalf,
        on: display
      )
    )
  }

  func testWindowMatchingRecognizesExactLeftMiddleAndRightThirds() {
    let display = DrillDisplay(
      id: "main",
      name: "Display",
      frame: DrillRect(x: 0, y: 24, width: 1200, height: 876)
    )

    for zone in [DrillZone.leftThird, .middleThird, .rightThird] {
      XCTAssertTrue(
        WindowDrillGeometry.matchesWindow(
          actual: zone.frame(in: display),
          target: zone.frame(in: display),
          for: zone,
          on: display
        ),
        "Expected an exact \(zone.rawValue) placement to match"
      )
    }
  }

  func testWindowMatchingDoesNotMistakeHalvesForThirds() {
    let display = DrillDisplay(
      id: "main",
      name: "Display",
      frame: DrillRect(x: 0, y: 24, width: 1200, height: 876)
    )

    XCTAssertFalse(
      WindowDrillGeometry.matchesWindow(
        actual: DrillZone.leftHalf.frame(in: display),
        target: DrillZone.leftThird.frame(in: display),
        for: .leftThird,
        on: display
      )
    )
    XCTAssertFalse(
      WindowDrillGeometry.matchesWindow(
        actual: DrillZone.rightHalf.frame(in: display),
        target: DrillZone.rightThird.frame(in: display),
        for: .rightThird,
        on: display
      )
    )
  }

  func testWindowMatchingAllowsBoundedMinimumWidthExpansionForThirds() {
    let display = DrillDisplay(
      id: "main",
      name: "Display",
      frame: DrillRect(x: 0, y: 24, width: 1200, height: 876)
    )
    let expandedFrames: [DrillZone: DrillRect] = [
      .leftThird: DrillRect(x: 0, y: 24, width: 500, height: 876),
      .middleThird: DrillRect(x: 350, y: 24, width: 500, height: 876),
      .rightThird: DrillRect(x: 700, y: 24, width: 500, height: 876),
    ]

    for zone in [DrillZone.leftThird, .middleThird, .rightThird] {
      XCTAssertTrue(
        WindowDrillGeometry.matchesWindow(
          actual: expandedFrames[zone]!,
          target: zone.frame(in: display),
          for: zone,
          on: display
        ),
        "Expected a minimum-width \(zone.rawValue) placement to match"
      )
    }
  }

  func testDisplayTopologyIgnoresOrderAndSubpixelNoise() {
    let original = [
      DrillDisplay(
        id: "main",
        name: "Built-in",
        frame: DrillRect(x: 0, y: 24, width: 1512, height: 958)
      ),
      DrillDisplay(
        id: "external",
        name: "External",
        frame: DrillRect(x: 1512, y: 0, width: 1920, height: 1080)
      ),
    ]
    let reorderedWithNoise = [
      DrillDisplay(
        id: "external",
        name: "Renamed External",
        frame: DrillRect(x: 1512.4, y: 0, width: 1919.6, height: 1080)
      ),
      DrillDisplay(
        id: "main",
        name: "Built-in Retina Display",
        frame: DrillRect(x: 0, y: 24.5, width: 1512, height: 957.5)
      ),
    ]

    XCTAssertTrue(
      WindowDrillGeometry.sameDisplayTopology(original, reorderedWithNoise)
    )
  }

  func testDisplayTopologyDetectsRealFrameOrIdentityChanges() {
    let original = [
      DrillDisplay(
        id: "main",
        name: "Built-in",
        frame: DrillRect(x: 0, y: 24, width: 1512, height: 958)
      )
    ]
    let resized = [
      DrillDisplay(
        id: "main",
        name: "Built-in",
        frame: DrillRect(x: 0, y: 24, width: 1352, height: 854)
      )
    ]
    let replacement = [
      DrillDisplay(
        id: "external",
        name: "External",
        frame: DrillRect(x: 0, y: 24, width: 1512, height: 958)
      )
    ]

    XCTAssertFalse(WindowDrillGeometry.sameDisplayTopology(original, resized))
    XCTAssertFalse(WindowDrillGeometry.sameDisplayTopology(original, replacement))
    XCTAssertFalse(WindowDrillGeometry.sameDisplayTopology(original, original + replacement))
  }

  private func hasPositiveIntersection(_ lhs: DrillRect, _ rhs: DrillRect) -> Bool {
    let overlapWidth = min(lhs.x + lhs.width, rhs.x + rhs.width) - max(lhs.x, rhs.x)
    let overlapHeight = min(lhs.y + lhs.height, rhs.y + rhs.height) - max(lhs.y, rhs.y)
    return overlapWidth > 0.0001 && overlapHeight > 0.0001
  }
}

private struct SeededGenerator: RandomNumberGenerator {
  var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func next() -> UInt64 {
    state = state &* 6_364_136_223_846_793_005 &+ 1
    return state
  }
}
