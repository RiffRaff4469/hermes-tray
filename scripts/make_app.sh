#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

mkdir -p HermesTray.app/Contents/MacOS HermesTray.app/Contents/Resources
cp .build/release/HermesTray HermesTray.app/Contents/MacOS/
cp support/Info.plist HermesTray.app/Contents/
codesign --force --deep -s - HermesTray.app

printf 'Built %s/HermesTray.app\nDrag to /Applications, then launch HermesTray.\n' "$PWD"
