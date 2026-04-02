#!/bin/bash
# LittleBrother Release Packaging Script
# Creates minimal tarball for distribution

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VERSION=${1:-$(grep 'version:' "$SCRIPT_DIR/../pubspec.yaml" | head -1 | awk '{print $2}')}
ARCH=$(uname -s | tr '[:upper:]' '[:lower:]')
TARBALL="$SCRIPT_DIR/../littlebrother_${VERSION}_${ARCH}.tar.gz"

echo "Packaging LittleBrother v${VERSION} for ${ARCH}..."

cd "$SCRIPT_DIR/.."

tar --exclude='.git' \
    --exclude='build/' \
    --exclude='.dart_tool/' \
    --exclude='.gradle' \
    --exclude='.idea/' \
    --exclude='.vscode/' \
    --exclude='*.iml' \
    --exclude='android/app/build/' \
    --exclude='android/build/' \
    --exclude='linux/build/' \
    --exclude='*.apk' \
    --exclude='*.aab' \
    --exclude='pubspec.lock' \
    --exclude='.packages' \
    --exclude='.flutter-plugins' \
    --exclude='.flutter-plugins-dependencies' \
    -czf "$TARBALL" .

echo "Created: $TARBALL"
ls -lh "$TARBALL"
echo ""
echo "To extract: tar -xzf $TARBALL"
echo "To build: cd to extracted dir, then 'flutter pub get && flutter build apk'"