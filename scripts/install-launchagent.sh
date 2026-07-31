#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_source="$repo_root/.build/mbar.app"
app_target="$HOME/Applications/mbar.app"
agent_path="$HOME/Library/LaunchAgents/dev.auhanson.mbar.plist"
log_dir="$HOME/Library/Logs/mbar"
uid="$(id -u)"

"$repo_root/scripts/build-app.sh" release >/dev/null

mkdir -p "$HOME/Applications" "$log_dir" "$(dirname "$agent_path")"
rm -rf "$app_target"
ditto "$app_source" "$app_target"

cat > "$agent_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>dev.auhanson.mbar</string>
  <key>ProgramArguments</key>
  <array>
    <string>$app_target/Contents/MacOS/mbar</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$log_dir/stdout.log</string>
  <key>StandardErrorPath</key>
  <string>$log_dir/stderr.log</string>
</dict>
</plist>
PLIST

plutil -lint "$agent_path" >/dev/null
launchctl bootout "gui/$uid" "$agent_path" 2>/dev/null || true
launchctl bootstrap "gui/$uid" "$agent_path"
launchctl kickstart -k "gui/$uid/dev.auhanson.mbar"

echo "$app_target"
