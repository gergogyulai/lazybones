#!/bin/zsh
# Builds build/Lazybones.app (ad-hoc signed).
#
#   Scripts/build.sh           release build
#   Scripts/build.sh --debug   debug build
#   open build/Lazybones.app
set -euo pipefail
cd "${0:A:h}/.."

config=release
[[ "${1:-}" == "--debug" ]] && config=debug

swift build -c "$config" --product Lazybones
BIN="$(swift build -c "$config" --show-bin-path)/Lazybones"

APP=build/Lazybones.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Lazybones"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# The ad blocker ships inside the app. Without it Lazybones still works, just without blocking.
[[ -d Extensions/uBOLite ]] || Scripts/fetch-ubol.sh || echo "warning: building without uBlock Origin Lite" >&2
[[ -d Extensions/uBOLite ]] && cp -R Extensions/uBOLite "$APP/Contents/Resources/uBOLite"

codesign --force --sign - "$APP"
echo "built $APP"
