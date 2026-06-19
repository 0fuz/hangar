# Hangar

A lightweight macOS menu bar app that turns your terminal workflows into one-click, toggleable snippets. No electron, no bloat — native Swift and AppKit.

<p align="center">
  <img src=".github/menu.png" width="45%" alt="Menu bar popover with grouped snippets, status dots, and per-group toggles">
</p>
<p align="center">
  <img src=".github/settings.png" width="80%" alt="Snippet editor showing a terminal snippet with its command, status, and the grouped sidebar">
</p>

## Why?

You keep the same workflows running all day — a build/watch command in one project, a TUI you paste into in another — each pinned to a folder and a command, often parked on its own desktop. They're easy to lose track of, and after a restart you have to remember to start them all again.

Hangar keeps them as a compact list in the menu bar. Flip a toggle to open iTerm2 (or Terminal) and run the command; flip it off to close it. Mark the ones you want back automatically when you log in.

## Features

- **Menu bar app** — always accessible, no dock icon
- **Terminal snippets** — open iTerm2 / Terminal and run a command with one toggle
- **Application snippets** — launch an app, optionally opening a specific project or file with it (e.g. an IDE + a project folder)
- **Groups** — organize snippets with dividers and flip a whole group with one toggle
- **Auto-start on login** — your pinned workflows come back after a restart
- **Native macOS** — drives your real terminal via AppleScript; no bundled shell, no reinvented terminal

## Build from source

```bash
cd Hangar
xcodebuild -scheme Hangar -configuration Release
```

Requires Xcode 15+ and macOS 14+.

## Usage

1. Click the Hangar icon in the menu bar.
2. Open **Settings** and add a snippet:
   - **Terminal** — choose iTerm2 or Terminal and enter a command. Use **Folder…** to prepend a `cd`, or type the full line yourself.
   - **Application** — choose an app, and optionally a project or file to open with it.
3. Toggle the snippet from the menu bar. Mark **Auto-start** to bring it back on login.

On first launch macOS asks to let Hangar **control** your terminal (Automation) — that's how it opens a window and runs your command. Allow it once.

## License

MIT
