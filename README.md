# TopTerm

A standalone native macOS menu-bar terminal drawer. Built with AppKit and SwiftTerm. All settings and sessions stay on your Mac; the app has no account, telemetry, server, or project integration.

[Website](https://chaosdeselva.github.io/TopTerm/) · [Source](https://github.com/ChaosDeSelva/TopTerm)

## Install

[Download TopTerm 0.1.0 for Apple silicon](https://github.com/ChaosDeSelva/TopTerm/releases/download/v0.1.0/TopTerm-0.1.0-arm64.dmg) (macOS 14 or later). Open the signed, notarized disk image and drag TopTerm into Applications.

## Use

Open `TopTerm.app`. Click its terminal icon in the menu bar, or press **Control + backtick**, to show or hide the drawer. Right-click the icon for the menu.

To choose different keys, click the shortcut in the drawer’s bottom-right corner, press **Command + comma**, or select **Show / Hide Shortcut…** from the menu. Record a combination such as **Option + Space**, then save it. The setting persists across launches; unavailable combinations leave the previous binding intact.

- Full available display width, starting at 50% of the usable display height.
- Drag the bottom edge to save a different height, or choose a preset using the percentage button.
- The expand button at the top right switches between full available height and the saved height. The hide button sits immediately to its right.
- Tabs run independent sessions of the macOS account’s login shell, with its usual configuration. The first tab starts in the home folder. A new tab inherits the current tab’s directory. The footer follows the local shell’s working directory without requiring shell configuration; inside a Git repository it also shows the branch and a `*` for uncommitted or untracked changes. Detached HEAD shows the short commit ID.
- Hiding the drawer preserves all sessions and running commands. Closing a tab terminates that tab. Closing the final tab hides the drawer; showing it again starts a fresh shell.
- **Quit & Terminate All Sessions** ends the app’s terminal sessions and their attached jobs. Processes that deliberately detach into their own Unix session are independent of the terminal.
- The drawer opens on the display containing the pointer and remains visible when another app gets focus.

| Shortcut | Action |
| --- | --- |
| Control + backtick | Show / hide from any app |
| Command + comma | Remap the show / hide shortcut |
| Command + T | New tab |
| Command + W | Close active tab |
| Command + Return | Full height / saved height |
| Command + 1–9 | Select tab |
| Command + Shift + [ / ] | Previous / next tab |
| Command + plus / minus | Change text size |
| Command + 0 | Reset text size |
| Command + C / V | Copy / paste |
| Command + Q | Quit and terminate sessions |

Escape is passed through to terminal programs. If another app has reserved Control + backtick, use the menu-bar icon; its menu reports the shortcut conflict.

## Build locally

Requires macOS 14 or later and Swift 6 or later (Xcode Command Line Tools are sufficient). All dependencies are included as local source. Building does not fetch packages or run Git.

```sh
zsh scripts/build.sh
open build/TopTerm.app
```

The local build uses an ad-hoc signature. The application runs outside the App Sandbox so local shells have their usual filesystem and tool access.

## Check

```sh
swift run --disable-sandbox TopTermGeometryChecks
swift build --disable-sandbox
.build/debug/TopTerm --self-test
```

The debug-only integration checks use temporary, isolated shell configuration. They cover shortcut persistence and conflicts, PTY I/O, live working-directory changes, Git branch and dirty-state refresh, tab isolation, hidden-session execution, resize delivery, alternate-screen restoration, foreground-job detection, and session-scoped termination. Geometry tests cover default sizing, height restoration, multiple-display coordinates, and invalid preferences.

## Source layout

- `Sources/TopTerm`: menu bar, panel, tabs, shell sessions, and keyboard controls.
- `Sources/TopTermCore`: display geometry.
- `Vendor/SwiftTerm`: pinned terminal engine source and MIT license.
- `Resources`: app bundle metadata and icon.
- `scripts`: local build and icon generation.
- `docs`: the static GitHub Pages website, published from `main`.

No project license has been selected yet. SwiftTerm retains its own MIT license; see `Vendor/SwiftTerm/LICENSE` and `Vendor/SwiftTerm/UPSTREAM.md`.
