import Foundation

public struct DexKey: Identifiable, Hashable, Sendable {
  public let label: String
  public let keyCode: UInt16

  public var id: UInt16 { keyCode }

  public init(_ label: String, _ keyCode: UInt16) {
    self.label = label
    self.keyCode = keyCode
  }
}

public enum KeyCatalog {
  public static let all: [DexKey] = [
    DexKey("A", 0), DexKey("B", 11), DexKey("C", 8), DexKey("D", 2),
    DexKey("E", 14), DexKey("F", 3), DexKey("G", 5), DexKey("H", 4),
    DexKey("I", 34), DexKey("J", 38), DexKey("K", 40), DexKey("L", 37),
    DexKey("M", 46), DexKey("N", 45), DexKey("O", 31), DexKey("P", 35),
    DexKey("Q", 12), DexKey("R", 15), DexKey("S", 1), DexKey("T", 17),
    DexKey("U", 32), DexKey("V", 9), DexKey("W", 13), DexKey("X", 7),
    DexKey("Y", 16), DexKey("Z", 6),
    DexKey("0", 29), DexKey("1", 18), DexKey("2", 19), DexKey("3", 20),
    DexKey("4", 21), DexKey("5", 23), DexKey("6", 22), DexKey("7", 26),
    DexKey("8", 28), DexKey("9", 25),
    DexKey("Space", 49), DexKey("Return", 36), DexKey("Tab", 48),
    DexKey("Escape", 53), DexKey("Delete", 51),
    DexKey("←", 123), DexKey("→", 124), DexKey("↓", 125), DexKey("↑", 126),
    DexKey("F1", 122), DexKey("F2", 120), DexKey("F3", 99),
    DexKey("F4", 118), DexKey("F5", 96), DexKey("F6", 97),
    DexKey("F7", 98), DexKey("F8", 100), DexKey("F9", 101),
    DexKey("F10", 109), DexKey("F11", 103), DexKey("F12", 111),
    DexKey("-", 27), DexKey("=", 24), DexKey("[", 33), DexKey("]", 30),
    DexKey(";", 41), DexKey("'", 39), DexKey(",", 43), DexKey(".", 47),
    DexKey("/", 44), DexKey("\\", 42), DexKey("`", 50),
  ]

  public static func key(forCode keyCode: UInt16) -> DexKey? {
    all.first { $0.keyCode == keyCode }
  }
}
