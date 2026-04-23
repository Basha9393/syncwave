#!/bin/bash
# setup.sh — Install SyncWave dependencies
# Run this on every Mac involved (sender and receivers)

set -e

echo "Setting up SyncWave dependencies..."

# Check for Homebrew
if ! command -v brew &>/dev/null; then
    echo "Homebrew not found. Install it from https://brew.sh then re-run this script."
    exit 1
fi

# Install libopus
if brew list opus &>/dev/null; then
    echo "✓ libopus already installed"
else
    echo "Installing libopus..."
    brew install opus
fi

# Check Xcode
if ! command -v xcodebuild &>/dev/null; then
    echo "⚠️  Xcode not found. Install Xcode from the Mac App Store."
    echo "   Command Line Tools alone are not sufficient for this project."
else
    XCODE_VER=$(xcodebuild -version | head -1)
    echo "✓ $XCODE_VER"
fi

# Check macOS version
MACOS_VER=$(sw_vers -productVersion)
MACOS_MAJOR=$(echo "$MACOS_VER" | cut -d. -f1)
MACOS_MINOR=$(echo "$MACOS_VER" | cut -d. -f2)

if [ "$MACOS_MAJOR" -lt 14 ] || ([ "$MACOS_MAJOR" -eq 14 ] && [ "$MACOS_MINOR" -lt 2 ]); then
    echo "⚠️  macOS $MACOS_VER detected. CoreAudio tap requires macOS 14.2 or later."
    echo "   This Mac cannot run SyncWave."
    exit 1
else
    echo "✓ macOS $MACOS_VER — CoreAudio tap API available"
fi

# Print libopus include/lib paths (useful for Xcode configuration)
OPUS_PREFIX=$(brew --prefix opus)
echo ""
echo "libopus paths (add to Xcode project settings):"
echo "  Header Search Paths: $OPUS_PREFIX/include"
echo "  Library Search Paths: $OPUS_PREFIX/lib"
echo "  Link with: -lopus"
echo ""
echo "Setup complete. Open the Xcode project and follow docs/ROADMAP.md."
