import Foundation

public enum TerminalApplication: String, Codable, CaseIterable, Identifiable, Sendable {
  case terminal
  case ghostty

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .terminal: "Terminal"
    case .ghostty: "Ghostty"
    }
  }

  public var bundleIdentifier: String {
    switch self {
    case .terminal: "com.apple.Terminal"
    case .ghostty: "com.mitchellh.ghostty"
    }
  }
}
