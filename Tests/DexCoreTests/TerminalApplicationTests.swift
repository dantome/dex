import XCTest

@testable import DexCore

final class TerminalApplicationTests: XCTestCase {
  func testOlderConfigurationKeepsTerminalAsDefault() throws {
    let configuration = try JSONDecoder().decode(
      DexConfiguration.self,
      from: Data(#"{"version":2,"shortcuts":[]}"#.utf8)
    )
    XCTAssertEqual(configuration.defaultTerminal, .terminal)
  }

  func testEveryTerminalPreferencePersists() throws {
    for terminal in TerminalApplication.allCases {
      let original = DexConfiguration(defaultTerminal: terminal)
      let repository = ConfigurationRepository()
      let decoded = try repository.decode(repository.encode(original))
      XCTAssertEqual(decoded, original)
    }
  }

  func testGhosttyLaunchDoesNotPassBareFilesToCocoa() {
    let command = "printf '%s\\n' \"a quote: '\" '$HOME; $(echo literal)'\nexit 17"
    let directory = URL(fileURLWithPath: "/tmp/DEX's project $HOME")
    for closeOnCompletion in [true, false] {
      let arguments = TerminalCommandScripts.ghosttyArguments(
        command: command,
        workingDirectory: directory,
        closeOnCompletion: closeOnCompletion
      )
      XCTAssertTrue(arguments.allSatisfy { $0.hasPrefix("--") })
      XCTAssertTrue(arguments.contains(
        "--initial-command=/bin/zsh -lc \(ShellEscaping.singleQuoted(command))"
      ))
      XCTAssertTrue(arguments.contains("--working-directory=\(directory.path)"))
      XCTAssertTrue(arguments.contains("--wait-after-command=\(!closeOnCompletion)"))
      XCTAssertTrue(arguments.contains("--abnormal-command-exit-runtime=0"))
      XCTAssertTrue(arguments.contains("--window-save-state=never"))
      XCTAssertTrue(arguments.contains("--quit-after-last-window-closed=true"))
    }
  }
}
