#!/usr/bin/env bash
# Installs tools and generates EarReader.xcodeproj.
set -euo pipefail
cd "$(dirname "$0")/.."

# ponytail: skip ffmpeg if any ffmpeg (e.g. ffmpeg-full) is already on PATH
if command -v ffmpeg >/dev/null; then
  grep -v '"ffmpeg"' Brewfile | brew bundle --file=-
else
  brew bundle
fi

want="$(cat .xcode-version)"
have="$(xcodebuild -version | head -1 | awk '{print $2}')"
[[ "$have" == "$want"* ]] || echo "warning: Xcode $have selected, CI uses $want" >&2

xcodegen generate
