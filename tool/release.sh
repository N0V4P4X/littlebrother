#!/bin/bash
# LittleBrother Release Packaging Script
# Creates minimal tarball for distribution
# Usage: ./release.sh [version] - defaults to pubspec.yaml version

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION=${1:-$(grep 'version:' "$PROJECT_DIR/pubspec.yaml" | head -1 | awk '{print $2}')}
ARCH=$(uname -s | tr '[:upper:]' '[:lower:]')

TEMP_TARBALL="/tmp/littlebrother_${VERSION}_${ARCH}.tar.gz"
FINAL_TARBALL="$PROJECT_DIR/littlebrother_${VERSION}_${ARCH}.tar.gz"

echo "Packaging LittleBrother v${VERSION} for ${ARCH}..."

tar --exclude='.git' \
    --exclude='build/' \
    --exclude='.dart_tool/' \
    --exclude='.gradle/' \
    --exclude='.idea/' \
    --exclude='.vscode/' \
    --exclude='*.iml' \
    --exclude='android/app/build/' \
    --exclude='android/build/' \
    --exclude='android/.gradle/' \
    --exclude='linux/build/' \
    --exclude='linux/.dart_tool/' \
    --exclude='linux/CMakeFiles/' \
    --exclude='linux/cmake_build/' \
    --exclude='macos/Flutter/ephemeral/' \
    --exclude='macos/Runner.xcworkspace/' \
    --exclude='macos/Runner.xcodeproj/' \
    --exclude='macos/RunnerTests/' \
    --exclude='windows/' \
    --exclude='ios/' \
    --exclude='*.apk' \
    --exclude='*.aab' \
    --exclude='*.lock' \
    --exclude='pubspec.lock' \
    --exclude='.packages' \
    --exclude='.flutter-plugins' \
    --exclude='.flutter-plugins-dependencies' \
    --exclude='test/' \
    --exclude='.github/' \
    -czf "$TEMP_TARBALL" -C "$PROJECT_DIR" .

mv "$TEMP_TARBALL" "$FINAL_TARBALL"

echo "Created: $FINAL_TARBALL"
ls -lh "$FINAL_TARBALL"
echo ""
echo "To extract: tar -xzf $FINAL_TARBALL"
echo "To build: cd to extracted dir, then 'flutter pub get && flutter build apk'"