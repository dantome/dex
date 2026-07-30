# Dex

Dex is a native Swift menu-bar app for macOS that turns a physical modifier key plus another key into an action. It is inspired by RCMD, defaults to Right Command, and is deliberately small and extensible.

The initial action types are:

- Open a macOS application by `.app` path or bundle identifier.
- Activate Finder or open a specific directory in Finder.
- Run a shell command in Terminal, which is useful for long-running dev servers.
- Run a shell command in the background and append output to `~/Library/Application Support/Dex/dex.log`.
- Open a URL.
- Run a named workflow from Apple's Shortcuts app.

Shortcuts may also add Shift, Control, Option, or Command to the selected trigger. The trigger's own modifier is implicit, so recording Right Command + D produces `Right ⌘ + D`, not a duplicated Command modifier. The global trigger can be Right Command, Right Option, Fn/Globe, or the corresponding supported left/control keys.

## Install

Dex requires macOS 14 or newer and the full Xcode toolchain.

```sh
cd /path/to/dex
./scripts/install.sh
```

The installer builds and signs `Dex.app`, copies it to `~/Applications`, removes its disposable staging bundle, and opens the app. This keeps Finder and Spotlight from showing the staging artifact as a third copy of Dex. It automatically uses an available Developer ID or Apple Development certificate so macOS keeps Accessibility approval across rebuilds. If no persistent signing identity is available, it falls back to ad-hoc signing and prints a warning. Set `DEX_SIGNING_IDENTITY` to override the selected identity.

Dex is a menu-bar-only app. Open the key-chord icon, choose **Settings…**, and grant Accessibility access when prompted. If macOS also asks for Input Monitoring, enable Dex there and relaunch it. Installing the `.app` before granting access gives macOS a stable app identity.

The General settings can hide Dex's menu-bar item while its shortcuts continue running. Reopen Dex from Applications or Spotlight whenever you need to bring Settings back. The same screen includes a validated JSON editor and copy button for moving the complete configuration to another Mac.

Choose **About Dex** from the menu-bar menu to see the app icon and installed version.

For a development build without installation:

```sh
swift run Dex
```

The packaged app is preferable for permission testing.

## Use

1. Open **Settings…** from the menu-bar icon.
2. Add a shortcut and choose its key and action.
3. Hold the configured physical trigger, Right Command by default, and press the shortcut key.

When a binding matches, Dex consumes the key press so the foreground app does not also handle it. Unmatched combinations keep their normal macOS behavior.

Dex keeps deleted shortcuts in **Recently Deleted** for 30 days by default, where they can be restored or permanently removed. Turn **Keep deleted shortcuts for 30 days** off in General settings to delete new shortcuts immediately. The **History** tab shows the newest 1,000 shortcut runs and can be cleared at any time.

For a dev server, create a **Run Command** action such as `npm run dev`, choose the project directory, and leave **Open in Terminal** enabled. Right Command + the selected key then opens a visible, long-lived Terminal session in that directory. Enable **Close Terminal on completion** for finite commands whose Terminal tab should close automatically when they finish.

To open Finder, choose the **Open Finder** action. Leave **Directory** empty to activate Finder, or choose a directory to open a Finder window at that location.

## Security model

Dex runs as the current macOS user. App, URL, and Apple Shortcut actions use native system APIs or tools. Shell actions can run arbitrary commands with the user's permissions; Dex does not elevate privileges. Review shell actions before adding them.

The configuration file is written with `0600` permissions at:

```text
~/Library/Application Support/Dex/shortcuts.json
```

Shortcut history is also private to the current user and stored with `0600` permissions at `~/Library/Application Support/Dex/history.json`.

## Development

```sh
cd /path/to/dex
swift build
swift test
./scripts/build-app.sh release
```

After editing the app icon in `Resources/DexAppIcon.svg`, regenerate the packaged macOS icon with:

```sh
./scripts/generate-icons.sh
```

The Swift package has two targets:

- `DexCore`: Codable models, key catalog, persistence, and shared utilities.
- `Dex`: SwiftUI/AppKit menu-bar app, global event tap, and action execution.
