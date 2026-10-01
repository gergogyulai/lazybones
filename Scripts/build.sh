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
# SwiftPM records the deployment target as the SDK the binary was built with, and AppKit then
# draws the app as it looked on that macOS: no Liquid Glass, old-style Settings window and
# controls. Record the SDK it was actually built against.
vtool -set-build-version macos "$(sed -n 's/^.*LSMinimumSystemVersion<\/key><string>\([^<]*\).*$/\1/p' Resources/Info.plist)" \
    "$(xcrun --show-sdk-version)" -replace -output "$APP/Contents/MacOS/Lazybones" "$APP/Contents/MacOS/Lazybones"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# What the About window shows under the version: the commit (marked if the tree had changes),
# when it was built and the SDK it was built against.
commit=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
[[ -n "$(git status --porcelain 2>/dev/null)" ]] && commit+="-dirty"
plist() { /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$APP/Contents/Info.plist"; }
plist LBGitCommit "$commit"
plist LBBuildDate "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
plist LBBuildSDK "$(xcrun --show-sdk-version)"
plist LBBuildConfiguration "$config"
# Drawn by Scripts/make-icon.swift.
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Official service logos (where each came from is in Resources/Brands/SOURCES.md).
mkdir -p "$APP/Contents/Resources/Brands"
cp Resources/Brands/*.{pdf,svg,png} "$APP/Contents/Resources/Brands/"

# The ad blocker ships inside the app. Without it Lazybones still works, just without blocking.
[[ -d Extensions/uBOLite ]] || Scripts/fetch-ubol.sh || echo "warning: building without uBlock Origin Lite" >&2
[[ -d Extensions/uBOLite ]] && cp -R Extensions/uBOLite "$APP/Contents/Resources/uBOLite"

codesign --force --sign - "$APP"
echo "built $APP"
