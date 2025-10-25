#!/bin/sh
# Update config.sub and config.guess for ARM64 support

SOURCE_DIR=$1

if [ -z "$SOURCE_DIR" ]; then
    echo "Usage: $0 <source_directory>"
    exit 1
fi

# Only update on ARM64 macOS - other platforms work fine with existing config files
ARCH=$(uname -m)
OS=$(uname -s)

if [ "$OS" != "Darwin" ] || [ "$ARCH" != "arm64" ]; then
    echo "Skipping config files update (not ARM64 Mac)"
    exit 0
fi

echo "Updating config.sub and config.guess in $SOURCE_DIR for ARM64 Mac support"

# Remove old files if they exist and are read-only
[ -f "$SOURCE_DIR/config.sub" ] && chmod +w "$SOURCE_DIR/config.sub" 2>/dev/null
[ -f "$SOURCE_DIR/config.guess" ] && chmod +w "$SOURCE_DIR/config.guess" 2>/dev/null

# Try to download latest config.sub
if ! curl -L -o "$SOURCE_DIR/config.sub" \
    'https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=HEAD'; then
    echo "Warning: Failed to download config.sub, build might fail on ARM64 Mac"
fi

# Try to download latest config.guess  
if ! curl -L -o "$SOURCE_DIR/config.guess" \
    'https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD'; then
    echo "Warning: Failed to download config.guess, build might fail on ARM64 Mac"
fi

# Make them executable if they exist
[ -f "$SOURCE_DIR/config.sub" ] && chmod +x "$SOURCE_DIR/config.sub"
[ -f "$SOURCE_DIR/config.guess" ] && chmod +x "$SOURCE_DIR/config.guess"

echo "Config files update completed"
exit 0

