# AuhansonVST

AuhansonVST is an independent macOS taskbar-style Dock alternative inspired by common taskbar workflows. It does not copy uBar code, assets, names, or private behavior.

## Public uBar feature inventory

Public listings and reviews describe uBar as having these capabilities:

| Feature | AuhansonVST status |
| --- | --- |
| Taskbar or Dock-style layout | Implemented as a taskbar panel |
| Running apps and open windows | Implemented: running apps plus window-title submenu |
| Group windows by application or show separately | Implemented as grouped-by-app; separate-window mode is planned |
| Pin/favorite apps, files, and folders | App pins implemented; files/folders planned |
| Multiple monitor support | Implemented: one bar per screen |
| Mirror mode across monitors | Implemented |
| Per-monitor apps/windows | Implemented using public CoreGraphics window bounds |
| Window previews on hover | Planned; current build shows window titles |
| Badges and app attention flashes | Attention state implemented; notification badges planned |
| Activity mode with CPU/RAM usage | Implemented via `ps` sampling |
| Position on any screen edge | Implemented: top, bottom, left, right |
| Adjustable rows/size/theme | Implemented: height, icon size, rows, dark/translucent style |
| Start/menu launcher | Implemented as Applications menu |
| System actions | Implemented: sleep, restart, shutdown, lock |
| Drag and drop | Planned |
| Trash/Desktop shortcuts | Implemented in the menu |
| Volume/media controls and progress | Planned |

## Build and run

```bash
swift build
.build/debug/AuhansonVST
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
