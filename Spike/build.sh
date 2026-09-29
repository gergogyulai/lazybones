#!/bin/zsh
# Builds build/Lull.app (ad-hoc signed). Run: ./build.sh && open build/Lull.app
set -euo pipefail
cd "${0:A:h}"
swift build -c release --product Lull
BIN="$(swift build -c release --show-bin-path)/Lull"

APP=build/Lull.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Lull"
cp Info.plist "$APP/Contents/Info.plist"
[[ -d Extensions/uBOLite ]] || ./fetch-ubol.sh
cp -R Extensions/uBOLite "$APP/Contents/Resources/uBOLite"
codesign --force --sign - "$APP"
echo "built $APP"
