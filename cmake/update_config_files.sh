#!/bin/sh
# Update config.sub and config.guess for ARM64 support
set -e

SOURCE_DIR=$1

if [ -z "$SOURCE_DIR" ]; then
    echo "Error: No source directory provided" >&2
    echo "Usage: $0 <source_directory>" >&2
    exit 1
fi

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory does not exist: $SOURCE_DIR" >&2
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

# Check if curl is available
if ! command -v curl >/dev/null 2>&1; then
    echo "Error: curl command not found. Cannot download config files." >&2
    echo "       Please install curl or manually update config.sub and config.guess" >&2
    exit 1
fi

# Remove old files if they exist and are read-only
[ -f "$SOURCE_DIR/config.sub" ] && chmod +w "$SOURCE_DIR/config.sub" 2>/dev/null
[ -f "$SOURCE_DIR/config.guess" ] && chmod +w "$SOURCE_DIR/config.guess" 2>/dev/null

# Download latest config files from GNU config repository
CONFIG_BASE_URL='https://git.savannah.gnu.org/cgit/config.git/plain'

# Try to download latest config.sub with timeout and retries
if ! curl -f -s -S -L --connect-timeout 30 --max-time 60 --retry 3 \
    -o "$SOURCE_DIR/config.sub" "$CONFIG_BASE_URL/config.sub"; then
    echo "Warning: Failed to download config.sub from $CONFIG_BASE_URL/config.sub" >&2
    echo "         Build might fail on ARM64 if config.sub doesn't support aarch64" >&2
else
    echo "Successfully downloaded config.sub"
fi

# Try to download latest config.guess with timeout and retries
if ! curl -f -s -S -L --connect-timeout 30 --max-time 60 --retry 3 \
    -o "$SOURCE_DIR/config.guess" "$CONFIG_BASE_URL/config.guess"; then
    echo "Warning: Failed to download config.guess from $CONFIG_BASE_URL/config.guess" >&2
    echo "         Build might fail on ARM64 if config.guess doesn't recognize this platform" >&2
else
    echo "Successfully downloaded config.guess"
fi

# Make them executable if they exist
if [ -f "$SOURCE_DIR/config.sub" ]; then
    chmod +x "$SOURCE_DIR/config.sub"
    echo "Made config.sub executable"
fi

if [ -f "$SOURCE_DIR/config.guess" ]; then
    chmod +x "$SOURCE_DIR/config.guess"
    echo "Made config.guess executable"
fi

echo "Config files update completed"
exit 0

