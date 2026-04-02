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

# Build exclude flags from .gitignore + additional platform builds
EXCLUDES="--exclude=.git"
while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    # Convert .gitignore patterns to tar --exclude patterns
    if [[ "$line" == *"/" ]]; then
        EXCLUDES="$EXCLUDES --exclude=${line%/}"
    else
        EXCLUDES="$EXCLUDES --exclude=$line"
    fi
done < "$PROJECT_DIR/.gitignore"

# Add additional platform-specific excludes not in .gitignore
EXCLUDES="$EXCLUDES --exclude=linux/CMakeFiles --exclude=linux/cmake_build"
EXCLUDES="$EXCLUDES --exclude=linux/flutter --exclude=linux/.dart_tool"
EXCLUDES="$EXCLUDES --exclude=macos/Flutter/ephemeral --exclude=macos/Runner.xcworkspace"
EXCLUDES="$EXCLUDES --exclude=macos/Runner.xcodeproj --exclude=macos/RunnerTests"
EXCLUDES="$EXCLUDES --exclude=windows --exclude=ios"
EXCLUDES="$EXCLUDES --exclude=.github --exclude=test"

tar $EXCLUDES -czf "$TEMP_TARBALL" -C "$PROJECT_DIR" .

mv "$TEMP_TARBALL" "$FINAL_TARBALL"

echo "Created: $FINAL_TARBALL"
ls -lh "$FINAL_TARBALL"
echo ""
echo "To extract: tar -xzf $FINAL_TARBALL"
echo "To build: cd to extracted dir, then 'flutter pub get && flutter build apk'"