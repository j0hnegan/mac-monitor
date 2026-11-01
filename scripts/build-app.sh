#!/bin/zsh
# Builds "Mac Monitor.app" into ./build. Pass --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)"
APP="build/Mac Monitor.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/MacMonitor" "$APP/Contents/MacOS/MacMonitor"
codesign --force --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf "/Applications/Mac Monitor.app"
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/Mac Monitor.app"
else
  echo "Built $APP"
fi
