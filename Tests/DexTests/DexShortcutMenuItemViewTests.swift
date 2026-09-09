import AppKit
import XCTest

@testable import Dex

@MainActor
final class DexShortcutMenuItemViewTests: XCTestCase {
  func testShortcutRowFillsItsContainerWhenMenuWidthChanges() async {
    let row = DexShortcutMenuItemView(
      title: "Open ChatGPT",
      shortcut: "Right ⌘ + C",
      width: 315
    ) {}
    let container = NSView(frame: row.frame)
    container.addSubview(row)

    // A longer result message can widen the menu beyond the shortcut labels.
    let widths: [CGFloat] = [380, 642, 315]
    for width in widths {
      container.setFrameSize(NSSize(width: width, height: 24))

      XCTAssertEqual(row.frame.width, width, accuracy: 0.5)
      XCTAssertEqual(row.frame.height, 24)
      XCTAssertTrue(row.hitTest(NSPoint(x: width - 14, y: 12)) === row)
    }
  }
}
