#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <version> [output-dir]" >&2
  exit 1
fi

if [[ -z "${GOMOBILE_BIND_PACKAGE:-}" ]]; then
  echo "GOMOBILE_BIND_PACKAGE is not set. Export the Go package path to bind." >&2
  exit 2
fi

if ! command -v go >/dev/null 2>&1; then
  echo "go is required but not found in PATH" >&2
  exit 3
fi

if ! command -v gomobile >/dev/null 2>&1; then
  echo "gomobile is required but not found in PATH" >&2
  exit 4
fi

VERSION="$1"
OUTPUT_ROOT="${2:-build/gomobile}"/"$VERSION"
ANDROID_OUT="$OUTPUT_ROOT/android"
APPLE_OUT="$OUTPUT_ROOT/apple"

mkdir -p "$ANDROID_OUT" "$APPLE_OUT"

AAR_PATH="$ANDROID_OUT/tachograph-$VERSION.aar"
XCFRAMEWORK_PATH="$APPLE_OUT/Tachograph.xcframework"
CHECKSUM_PATH="$OUTPUT_ROOT/checksums.txt"

# Android build (arm64-v8a & x86_64)
ANDROID_TARGETS="android/arm64,android/amd64"

echo "[gomobile] Building Android AAR → $AAR_PATH"
gomobile bind \
  -target="$ANDROID_TARGETS" \
  -androidapi 24 \
  -o "$AAR_PATH" \
  "$GOMOBILE_BIND_PACKAGE"

# iOS build (device + simulator)
IOS_TARGETS="ios,iossimulator"

echo "[gomobile] Building Apple xcframework → $XCFRAMEWORK_PATH"
gomobile bind \
  -target="$IOS_TARGETS" \
  -o "$XCFRAMEWORK_PATH" \
  "$GOMOBILE_BIND_PACKAGE"

# Checksums for reproducibility
sha256sum "$AAR_PATH" "$XCFRAMEWORK_PATH" > "$CHECKSUM_PATH"

echo "Artefacts written to $OUTPUT_ROOT"
