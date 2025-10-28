#!/bin/sh
# Update config.sub and config.guess for ARM64 support

SOURCE_DIR=$1

if [ -z "$SOURCE_DIR" ]; then
    echo "Usage: $0 <source_directory>"
    exit 1
fi

# Update on ARM64 platforms (macOS and Linux) - old config files don't recognize aarch64
ARCH=$(uname -m)
OS=$(uname -s)

# Check if we're on ARM64 (macOS uses "arm64", Linux uses "aarch64")
if [ "$ARCH" != "arm64" ] && [ "$ARCH" != "aarch64" ]; then
    echo "Skipping config files update (not ARM64 platform: $ARCH)"
    exit 0
fi

echo "Updating config.sub and config.guess in $SOURCE_DIR for ARM64 support ($OS $ARCH)"

# Remove old files if they exist and are read-only
[ -f "$SOURCE_DIR/config.sub" ] && chmod +w "$SOURCE_DIR/config.sub" 2>/dev/null
[ -f "$SOURCE_DIR/config.guess" ] && chmod +w "$SOURCE_DIR/config.guess" 2>/dev/null

# Try to download latest config.sub
if ! curl -f -L -o "$SOURCE_DIR/config.sub" \
    'https://git.savannah.gnu.org/cgit/config.git/plain/config.sub'; then
    echo "Warning: Failed to download config.sub, build might fail on ARM64"
fi

# Try to download latest config.guess  
if ! curl -f -L -o "$SOURCE_DIR/config.guess" \
    'https://git.savannah.gnu.org/cgit/config.git/plain/config.guess'; then
    echo "Warning: Failed to download config.guess, build might fail on ARM64"
fi

# Make them executable if they exist
[ -f "$SOURCE_DIR/config.sub" ] && chmod +x "$SOURCE_DIR/config.sub"
[ -f "$SOURCE_DIR/config.guess" ] && chmod +x "$SOURCE_DIR/config.guess"

echo "Config files update completed"
exit 0

