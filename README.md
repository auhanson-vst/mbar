# mbar

mbar is an independent macOS taskbar-style Dock alternative inspired by common taskbar workflows. It does not copy uBar code, assets, names, or private behavior.

## Public uBar feature inventory

Public listings and reviews describe uBar as having these capabilities:

| Feature | mbar status |
| --- | --- |
| Taskbar or Dock-style layout | Implemented as a taskbar panel |
| Auto-hide/reveal on edge hover | Implemented by default with a thin screen-edge trigger |
| Running apps and open windows | Implemented: running apps plus window-title submenu |
| Group windows by application or show separately | Implemented as grouped-by-app; separate-window mode is planned |
| Pin/favorite apps, files, and folders | App pins implemented; files/folders planned |
| Multiple monitor support | Implemented: one bar per screen |
| Mirror mode across monitors | Implemented as the default behavior: every display shows all open apps |
| Per-monitor apps/windows | Replaced by all-open-apps-on-every-display behavior |
| Window previews on hover | Planned; current build shows window titles |
| Badges and app attention flashes | Attention state implemented; notification badges planned |
| Activity mode with CPU/RAM usage | Implemented via `ps` sampling |
| Position on any screen edge | Implemented: top, bottom, left, right |
| Adjustable rows/size/theme | Implemented: height, icon size, rows, dark/translucent style |
| Start/menu launcher | Implemented: Applications tile opens an icon popup of installed apps |
| System actions | Implemented: sleep, restart, shutdown, lock |
| Drag and drop | Planned |
| Trash/Desktop shortcuts | Implemented in the menu |
| Volume/media controls and progress | Planned |

## Build and run

```bash
swift build
.build/debug/mbar
```

## Run at login with LaunchAgent

Build and install a stable `.app` bundle:

```bash
scripts/install-launchagent.sh
```

This installs:

- `~/Applications/mbar.app`
- `~/Library/LaunchAgents/dev.auhanson.mbar.plist`

The app bundle uses the stable bundle identifier `dev.auhanson.mbar`, which helps macOS keep Accessibility/TCC permissions across rebuilds.

Window titles require Accessibility permission. For stable permissions across rebuilds, create a local code-signing identity once before installing:

```bash
scripts/create-local-codesign-cert.sh
scripts/install-launchagent.sh
```

After switching from ad-hoc signing to the local signing identity, re-enable `mbar` once in System Settings → Privacy & Security → Accessibility.

For best results, hide the native Dock:

```bash
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 1000
defaults write com.apple.dock autohide-time-modifier -float 0
launchctl kickstart -k "gui/$(id -u)/com.apple.Dock.agent"
```

## Notes

Window control is intentionally limited to public macOS APIs unless Accessibility permission is granted. The app can list public window titles from CoreGraphics and activate apps through `NSWorkspace`.

The default UX hides until the pointer touches the configured screen edge, then quickly reveals a single translucent Dock-style section containing a centered icon-only strip ordered as pinned/running apps, additional open apps, a separator, native Applications folder icon, and native Trash icon. Every display shows the same deduplicated open-app set. The Applications tile opens a compact icon grid of installed apps.

Right-click empty space on mbar to open a Dock-style context menu with settings, activity mode, position, system settings, and quit actions. The settings window uses a left sidebar with sections for layout, built-in items, behavior, and system helpers. It exposes live controls for position, rows, bar size, icon size, item spacing, Finder/Applications/Trash visibility, activity mode, Accessibility status, and native Dock helpers.

Drag app icons within the bar to reorder/pin them. While dragging, mbar stays open and shows a stable insertion marker for the drop position. Drag a pinned app icon out of the expanded interaction area to unpin it.

After dropping, mbar preserves the revealed state instead of immediately hiding.

The normal hover keep-alive region is tight so the bar hides promptly. During drag, the keep-alive region expands substantially. App icons show Dock alert badges when macOS exposes them through Accessibility, with a visible-window-count fallback for apps with multiple windows.

mbar also hides when you type or click outside the bar/application grid.

Reveal and hide use a Dock-like slide animation from the configured screen edge.

Window title menus prefer Accessibility API titles, then fall back to CoreGraphics titles and generated labels for untitled visible windows. macOS requires granting mbar Accessibility permission for titles that match real app/window titles. Hovering over an app icon for 0.75 seconds shows an animated window-title list above the icon.

When Accessibility permission is granted, activating an app from mbar unminimizes its windows before bringing the app forward.

Finder is always filtered out of mbar, even if macOS reports it as a running app or it was previously saved in pinned items.
