#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_source="$repo_root/.build/mbar.app"
app_target="$HOME/Applications/mbar.app"
app_new="$HOME/Applications/.mbar.app.new"
app_previous="$HOME/Applications/.mbar.app.previous"
agent_path="$HOME/Library/LaunchAgents/dev.auhanson.mbar.plist"
agent_staged="$HOME/Library/LaunchAgents/.dev.auhanson.mbar.plist.new"
log_dir="$HOME/Library/Logs/mbar"
uid="$(id -u)"
cutover_complete=0

rollback() {
  local status=$?
  if [[ "$status" -ne 0 && "$cutover_complete" -eq 0 ]]; then
    rm -rf "$app_target"
    if [[ -d "$app_previous" ]]; then
      mv "$app_previous" "$app_target"
    fi
    rm -rf "$app_new"
    rm -f "$agent_staged"
    if [[ -f "$agent_path" ]]; then
      launchctl bootstrap "gui/$uid" "$agent_path" 2>/dev/null || true
      launchctl kickstart -k "gui/$uid/dev.auhanson.mbar" 2>/dev/null || true
    fi
  fi
  exit "$status"
}
trap rollback EXIT

"$repo_root/scripts/build-app.sh" release >/dev/null

mkdir -p "$HOME/Applications" "$log_dir" "$(dirname "$agent_path")"
rm -rf "$app_new" "$app_previous"
ditto "$app_source" "$app_new"
codesign --verify --deep --strict "$app_new" >/dev/null

cat > "$agent_staged" <<PLIST
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

plutil -lint "$agent_staged" >/dev/null

if [[ -d "$app_target" ]]; then
  mv "$app_target" "$app_previous"
fi
mv "$app_new" "$app_target"
mv "$agent_staged" "$agent_path"

launchctl bootout "gui/$uid" "$agent_path" 2>/dev/null || true
launchctl bootstrap "gui/$uid" "$agent_path"
launchctl kickstart -k "gui/$uid/dev.auhanson.mbar"

cutover_complete=1
trap - EXIT
rm -rf "$app_previous"
echo "$app_target"
