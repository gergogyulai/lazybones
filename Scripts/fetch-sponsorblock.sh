#!/bin/zsh
# Downloads the latest SponsorBlock Safari build into Extensions/SponsorBlock.
set -euo pipefail
cd "${0:A:h}/.."
url=$(curl -fsSL https://api.github.com/repos/ajayyy/SponsorBlock/releases/latest \
  | python3 -c 'import json,sys; print(next(a["browser_download_url"] for a in json.load(sys.stdin)["assets"] if a["name"] == "SafariExtension.zip"))')
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/sponsorblock.zip" "$url"
rm -rf Extensions/SponsorBlock
mkdir -p Extensions
unzip -q "$tmp/sponsorblock.zip" -d Extensions/SponsorBlock
echo "fetched SponsorBlock $(basename "$(dirname "$url")")"
