#!/bin/zsh
# Renders the launch-screen storyboard frames and app icon artwork using the
# app's own SwiftUI sources (compiled for macOS). Output goes to the directory
# given as $2.
#
#   tools/render_assets.sh frames build/launch-frames
#   tools/render_assets.sh icons  duova/Assets.xcassets/AppIcon.appiconset
set -euo pipefail

mode="${1:?mode: frames|icons}"
out="${2:?output directory}"
root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/duova"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

cp "$root/tools/render_launch_frames.swift" "$tmp/main.swift"
xcrun swiftc -O -swift-version 5 -default-isolation MainActor \
  -o "$tmp/render" \
  "$tmp/main.swift" \
  "$src/DesignSystem/DuovaPalette.swift" \
  "$src/DesignSystem/DuovaTheme.swift" \
  "$src/DesignSystem/Motion.swift" \
  "$src/DesignSystem/DuovaMark.swift" \
  "$src/DesignSystem/DuovaLockup.swift" \
  "$src/DesignSystem/ServiceMark.swift" \
  "$src/Features/Library/ServiceCatalog.swift" \
  "$src/Features/Launch/LaunchVariant.swift" \
  "$src/Features/Launch/LaunchGeometry.swift" \
  "$src/Features/Launch/LaunchTimeline.swift" \
  "$src/Features/Launch/LaunchScene.swift"

"$tmp/render" "$mode" "$out"
