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

For best results, hide the native Dock:

```bash
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 1000
defaults write com.apple.dock autohide-time-modifier -float 0
launchctl kickstart -k "gui/$(id -u)/com.apple.Dock.agent"
```

## Notes

Window control is intentionally limited to public macOS APIs unless Accessibility permission is granted. The app can list public window titles from CoreGraphics and activate apps through `NSWorkspace`.

The default UX hides until the pointer touches the configured screen edge, then reveals a centered icon-only strip ordered as pinned/running apps, additional open apps, a separator, Applications, and Trash. Every display shows the same open-app set. The Applications tile opens a direct popup of installed apps with icons.
