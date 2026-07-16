import SwiftUI

/// A simple, native mark for Dex in the macOS menu bar.
struct DexLogoMark: View {
  var body: some View {
    Image(systemName: "d.circle")
      .accessibilityLabel("Dex")
  }
}
