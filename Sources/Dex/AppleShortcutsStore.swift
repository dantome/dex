import Combine
import Foundation

@MainActor
final class AppleShortcutsStore: ObservableObject {
  @Published private(set) var names: [String] = []
  @Published private(set) var errorMessage: String?
  @Published private(set) var isLoading = false

  private var hasLoaded = false

  func loadIfNeeded() {
    guard !hasLoaded else { return }
    reload()
  }

  func reload() {
    guard !isLoading else { return }

    isLoading = true
    errorMessage = nil

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let result = Result { try Self.fetchNames() }

      DispatchQueue.main.async {
        guard let self else { return }
        self.isLoading = false
        self.hasLoaded = true

        switch result {
        case .success(let names):
          self.names = names
        case .failure(let error):
          self.names = []
          self.errorMessage = error.localizedDescription
        }
      }
    }
  }

  private nonisolated static func fetchNames() throws -> [String] {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
    process.arguments = ["list"]
    process.standardOutput = output
    process.standardError = output

    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    let text = String(decoding: data, as: UTF8.self)
    guard process.terminationStatus == 0 else {
      let detail = text.trimmingCharacters(in: .whitespacesAndNewlines)
      throw AppleShortcutsStoreError.listFailed(detail: detail)
    }

    return Array(
      Set(
        text
          .split(whereSeparator: \.isNewline)
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
      )
    )
    .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }
}

private enum AppleShortcutsStoreError: LocalizedError {
  case listFailed(detail: String)

  var errorDescription: String? {
    switch self {
    case .listFailed(let detail) where !detail.isEmpty:
      return "Could not read Apple Shortcuts: \(detail)"
    case .listFailed:
      return "Could not read Apple Shortcuts."
    }
  }
}
