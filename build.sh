#!/bin/bash
set -e

echo "Building ClipHistory..."

cd "$(dirname "$0")"

swift build -c release 2>&1

APP_DIR="ClipHistory.app"
BINARY=".build/release/ClipHistory"

if [ ! -f "$BINARY" ]; then
    echo "Build failed. Trying debug build..."
    swift build 2>&1
    BINARY=".build/debug/ClipHistory"
fi

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Build failed"
    exit 1
fi

echo "Creating app bundle..."

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BINARY" "$APP_DIR/Contents/MacOS/ClipHistory"
cp "Resources/Info.plist" "$APP_DIR/Contents/"

echo ""
echo "Build complete!"
echo "App: $(pwd)/$APP_DIR"
echo ""
echo "To run:"
echo "  open $APP_DIR"
echo ""
echo "To install:"
echo "  cp -r $APP_DIR /Applications/"
echo ""
echo "To uninstall:"
echo "  rm -rf /Applications/ClipHistory.app"
echo "  rm -rf ~/Library/Application\\ Support/ClipHistory"
