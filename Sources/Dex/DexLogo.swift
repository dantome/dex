import AppKit
import SwiftUI

struct DexLogoMark: View {
  var body: some View {
    Image(nsImage: Self.templateImage)
      .renderingMode(.template)
      .accessibilityLabel("Dex")
  }

  /// The monochrome companion to `Resources/DexLogo.svg`. Template images let
  /// macOS apply the correct menu-bar tint for both normal and pressed states.
  static let templateImage: NSImage = {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
      let scale = min(rect.width, rect.height) / 256
      let xOffset = rect.midX - (128 * scale)
      let yOffset = rect.midY - (128 * scale)

      func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: xOffset + (x * scale), y: yOffset + (y * scale))
      }

      let path = NSBezierPath()
      path.lineWidth = min(rect.width, rect.height) * 24 / 256
      path.lineCapStyle = .round
      path.move(to: point(62, 62))
      path.line(to: point(107, 107))
      path.move(to: point(149, 107))
      path.line(to: point(194, 62))
      path.move(to: point(107, 149))
      path.line(to: point(62, 194))
      path.move(to: point(149, 149))
      path.line(to: point(194, 194))

      NSColor.black.setStroke()
      path.stroke()
      return true
    }
    image.isTemplate = true
    return image
  }()
}
