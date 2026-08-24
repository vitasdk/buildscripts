#!/bin/sh
# Prepare an x86_64 macOS cross environment on an Apple silicon build machine:
# generate <triplet>-prefixed wrappers over the system clang so autotools
# configure scripts find the cross tools the same way they do for mingw, musl
# or FreeBSD hosts.
#
# Apple's SDK licence keeps it on Apple hardware, so this is how an x86_64 SDK
# is produced without osxcross: the same Xcode toolchain the arm64 build uses,
# with -arch x86_64. Nothing is downloaded.
#
# Usage: setup-macos-cross.sh <destdir> [arch]
#   e.g. setup-macos-cross.sh /opt/macos-cross x86_64
# Afterwards add <destdir>/bin to PATH and configure with
#   -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/<arch>-apple-darwin.cmake
#
# Requires: Xcode or the Command Line Tools (clang, xcrun).

set -eu

destdir=${1:?usage: $0 <destdir> [arch]}
arch=${2:-x86_64}

case "$arch" in
    x86_64|arm64) ;;
    *) echo "unsupported arch: $arch" >&2; exit 1 ;;
esac

command -v clang >/dev/null || { echo "clang not found" >&2; exit 1; }
sdk=$(xcrun --show-sdk-path)
[ -d "$sdk" ] || { echo "no macOS SDK at $sdk" >&2; exit 1; }

triplet="${arch}-apple-darwin"
bindir="$destdir/bin"
mkdir -p "$bindir"

# clang wrappers under the gcc names autotools probes for a --host triplet.
# The SDK path is pinned here so the wrappers do not depend on the caller's
# environment.
for tool in gcc:clang g++:clang++ cc:clang c++:clang++; do
    name=${tool%%:*}
    real=${tool##*:}
    cat > "$bindir/${triplet}-${name}" <<WRAP
#!/bin/sh
exec ${real} -arch ${arch} -isysroot ${sdk} "\$@"
WRAP
    chmod +x "$bindir/${triplet}-${name}"
done

# The rest of the toolchain is architecture agnostic on macOS; it only needs
# the prefixed names. These are wrappers rather than symlinks because the
# tools in /usr/bin are xcrun shims that dispatch on their own argv[0]: a link
# named <triplet>-ar makes the shim look for a developer tool by that name and
# fail. Execing the real path keeps argv[0] the name xcrun expects.
#
# ld and as are left out on purpose: clang drives them and passes the
# architecture, a bare prefixed wrapper would not.
for tool in ar ranlib strip nm lipo otool; do
    real=$(command -v "$tool" || true)
    [ -n "$real" ] || continue
    cat > "$bindir/${triplet}-${tool}" <<WRAP
#!/bin/sh
exec ${real} "\$@"
WRAP
    chmod +x "$bindir/${triplet}-${tool}"
done

echo "macOS ${arch} cross environment ready:"
echo "  export PATH=${bindir}:\$PATH"
echo "  toolchain triplet: ${triplet}"
