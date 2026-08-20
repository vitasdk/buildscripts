#!/bin/sh
# Prepare a FreeBSD cross environment on a Linux build machine:
# download the FreeBSD base system, extract the parts that form a sysroot
# (libs and headers) and generate <triplet>-prefixed compiler wrappers over
# clang so autotools-based configure scripts find the cross tools the same
# way they do for mingw or musl hosts.
#
# Usage: setup-freebsd-cross.sh <freebsd-version> <destdir> [arch]
#   e.g. setup-freebsd-cross.sh 14.3 /opt/freebsd-cross x86_64
# Afterwards add <destdir>/bin to PATH and configure with
#   -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/<arch>-unknown-freebsd.cmake
#
# Requires: clang, lld, llvm (llvm-ar etc.), curl, xz.

set -eu

version=${1:?usage: $0 <freebsd-version> <destdir> [arch]}
destdir=${2:?usage: $0 <freebsd-version> <destdir> [arch]}
arch=${3:-x86_64}

case "$arch" in
    x86_64)  fbsd_arch=amd64 ;;
    aarch64) fbsd_arch=arm64 ;;
    *) echo "unsupported arch: $arch" >&2; exit 1 ;;
esac

triplet="${arch}-unknown-freebsd${version%%.*}"
sysroot="$destdir/sysroot"
bindir="$destdir/bin"
mkdir -p "$sysroot" "$bindir"

base_url="https://download.freebsd.org/releases/${fbsd_arch}/${version}-RELEASE/base.txz"
echo "Fetching $base_url"
curl -fL "$base_url" |
    tar -xJf - -C "$sysroot" ./lib ./usr/lib ./usr/include ./usr/libdata

# clang wrappers under the gcc names autoconf probes for a --host triplet.
# -fuse-ld=lld reaches every invocation, compile-only ones included, and the
# driver warns about it there; the callers never wrote that flag, so a build
# with -Werror must not die on it.
for tool in gcc:clang g++:clang++ cc:clang c++:clang++; do
    name=${tool%%:*}
    real=${tool##*:}
    cat > "$bindir/${triplet}-${name}" <<WRAP
#!/bin/sh
exec ${real} --target=${triplet} --sysroot=${sysroot} -fuse-ld=lld \
    -Wno-unused-command-line-argument "\$@"
WRAP
    chmod +x "$bindir/${triplet}-${name}"
done

# Prefixed binutils over the llvm implementations.
for tool in ar ranlib nm strip objcopy objdump readelf; do
    real=$(command -v "llvm-${tool}" || true)
    [ -n "$real" ] || { echo "missing llvm-${tool}" >&2; exit 1; }
    ln -sf "$real" "$bindir/${triplet}-${tool}"
done

echo "FreeBSD ${version} ${arch} cross environment ready:"
echo "  export PATH=${bindir}:\$PATH"
echo "  toolchain triplet: ${triplet}"
