#!/bin/zsh
# Downloads the latest uBlock Origin Lite Safari build into Extensions/uBOLite.
set -euo pipefail
cd "${0:A:h}"
url=$(curl -fsSL https://api.github.com/repos/uBlockOrigin/uBOL-home/releases/latest \
  | python3 -c 'import json,sys; print(next(a["browser_download_url"] for a in json.load(sys.stdin)["assets"] if a["name"].endswith(".safari.zip")))')
tmp=$(mktemp -d)
curl -fsSL -o "$tmp/ubol.zip" "$url"
rm -rf Extensions/uBOLite
mkdir -p Extensions
unzip -q "$tmp/ubol.zip" -d Extensions/uBOLite
rm -rf "$tmp"
echo "fetched $(basename "$url")"
