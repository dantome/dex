---
name: customize-dex
description: Add, edit, remove, or troubleshoot shortcuts in DEX; change its global trigger or preferences; or extend the DEX macOS app itself. Use when a user asks an AI agent to make DEX open an app, Finder location, URL, Apple Shortcut, or shell command; automate a development workflow such as restarting a local server; resolve a binding conflict; or customize this repository's Swift code.
---

# Customize DEX

Turn a plain-language workflow into a safe DEX shortcut or a tested change to the app.

## Choose the workflow

- For a personal shortcut or preference, update the user's DEX configuration.
- For a new action type, UI behavior, or product-level change, edit the repository and add or update tests.
- Never run a configured shell command merely to test the configuration unless the user explicitly asks.

## Add or edit a shortcut

1. Read `Sources/DexCore/Models.swift` and `Sources/DexCore/KeyCatalog.swift` from the repository before editing. Treat them as the source of truth for the current JSON schema, action kinds, trigger values, modifiers, labels, and macOS virtual key codes.
2. Inspect `~/Library/Application Support/Dex/shortcuts.json`. If it does not exist, ask the user to launch DEX once or construct a complete `DexConfiguration` using the current model defaults.
3. Preserve every unrelated field and shortcut. Reuse an existing shortcut when the request is clearly an edit; otherwise generate a new UUID.
4. Choose an unused binding when the user did not specify one. The configured physical trigger is implicit: do not also put its equivalent in `binding.modifiers`. Only use `shift`, `control`, `option`, or `command` for additional modifiers.
5. Validate inputs without executing the action:
   - Confirm an application target or working directory exists.
   - Require an absolute `http://` or `https://` URL.
   - Check Apple Shortcut names with `shortcuts list` when available.
   - Review shell commands for obvious destructive behavior, credential exposure, or an incorrect working directory.
6. Back up the original configuration before writing. Write valid JSON atomically and preserve private `0600` permissions.
7. Apply the change. DEX does not automatically reload external file edits while running. Either relaunch DEX or open **General → Configuration**, choose **Reload from Disk**, review the JSON, and choose **Save Changes**.
8. Report the resulting chord, action, and any assumption the user may want to adjust.

## Action shapes

Use the exact current Codable model from `Models.swift`. The action-specific fields are:

- `launchApplication`: `target`
- `openFinder`: optional `directory`
- `runCommand`: `command`, optional `workingDirectory`, `inTerminal`, and `closeTerminalOnCompletion`
- `openURL`: `url`
- `runAppleShortcut`: `name`

For a long-running local server, prefer `inTerminal: true` and `closeTerminalOnCompletion: false`. For a finite restart script, set the close behavior from the user's preference rather than guessing.

## Change the app

1. Inspect the relevant source and existing tests before editing.
2. Keep model and persistence behavior in `DexCore`; keep SwiftUI, AppKit, global monitoring, and action execution in `Dex`.
3. Preserve backward decoding defaults when changing persisted data. Increment the configuration version only when a real migration requires it.
4. Run `swift test`. For packaging or permission-sensitive work, also run `./scripts/build-app.sh release` and explain that the installed app is preferable for Accessibility testing.
