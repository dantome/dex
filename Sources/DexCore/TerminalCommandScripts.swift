import Foundation

public enum TerminalCommandScripts {
  public static func command(
    _ command: String,
    workingDirectory: URL,
    closeScriptURL: URL?
  ) -> String {
    var script = """
      #!/bin/zsh
      cd -- \(ShellEscaping.singleQuoted(workingDirectory.path))
      /bin/zsh -lc \(ShellEscaping.singleQuoted(command))
      """

    if let closeScriptURL {
      script += """

        exit_status=$?
        terminal_tty=$(/usr/bin/tty)
        ( /usr/bin/osascript \(ShellEscaping.singleQuoted(closeScriptURL.path)) "$terminal_tty" ) >/dev/null 2>&1 &!
        exit "$exit_status"
        """
    }

    return script
  }

  public static let closeTerminal = """
    on closeMatchingTab(targetTTY)
      tell application "Terminal"
        repeat with terminalWindow in windows
          repeat with terminalTab in tabs of terminalWindow
            if (tty of terminalTab as text) is targetTTY then
              if busy of terminalTab then return false

              if (count tabs of terminalWindow) is 1 then
                close terminalWindow
              else
                close terminalTab
              end if
              return true
            end if
          end repeat
        end repeat
      end tell
      return false
    end closeMatchingTab

    on run argv
      set targetTTY to item 1 of argv
      repeat 50 times
        if closeMatchingTab(targetTTY) then return
        delay 0.1
      end repeat
    end run
    """
}
