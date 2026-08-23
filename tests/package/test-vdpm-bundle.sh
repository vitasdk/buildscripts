#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/buildscripts-vdpm-bundle.XXXXXXXX")
cleanup() { rm -rf -- "$temporary_directory"; }
trap cleanup EXIT

host=x86_64-w64-mingw32
root="$temporary_directory/input/vdpm-test-$host"
mkdir -p "$root/bin" "$root/share/vdpm/msys/usr/bin" "$root/share/vdpm/licenses"
printf 'frontend\n' > "$root/bin/vdpm.exe"
printf 'pacman\n' > "$root/share/vdpm/msys/usr/bin/pacman.exe"
printf 'channel\n' > "$root/share/vdpm/msys/usr/bin/vdpm-channel.exe"
printf 'runtime\n' > "$root/share/vdpm/msys/usr/bin/msys-2.0.dll"
printf 'refresh\n' > "$root/share/vdpm/refresh-repositories.ps1"
printf 'notices\n' > "$root/share/vdpm/THIRD_PARTY_NOTICES.md"
printf 'license\n' > "$root/share/vdpm/licenses/vdpm-LGPL-2.1.txt"
printf 'license\n' > "$root/share/vdpm/licenses/pacman-GPL-2.0.txt"
printf 'schema_version=1\nhost=%s\n' "$host" > \
	"$root/share/vdpm/release-info.txt"
bundle="$temporary_directory/vdpm.tar.bz2"
tar -cjf "$bundle" -C "$temporary_directory/input" "$(basename "$root")"
if command -v sha256sum >/dev/null; then
	digest=$(sha256sum "$bundle")
else
	digest=$(shasum -a 256 "$bundle")
fi
digest=${digest%% *}

sdk="$temporary_directory/sdk"
"$repository_root/scripts/install-vdpm-bundle.sh" \
	"$bundle" "$digest" "$sdk" "$host"
test -f "$sdk/bin/vdpm.exe"
test -f "$sdk/share/vdpm/msys/usr/bin/pacman.exe"
test -f "$sdk/share/vdpm/msys/usr/bin/vdpm-channel.exe"
test -f "$sdk/share/vdpm/msys/usr/bin/msys-2.0.dll"

if [[ ${digest:0:1} == 0 ]]; then
	bad_digest=1${digest:1}
else
	bad_digest=0${digest:1}
fi
if "$repository_root/scripts/install-vdpm-bundle.sh" \
	"$bundle" "$bad_digest" "$temporary_directory/bad-hash" "$host"; then
	printf 'vdpm bundle with a bad hash was accepted\n' >&2
	exit 1
fi
if "$repository_root/scripts/install-vdpm-bundle.sh" \
	"$bundle" "$digest" "$temporary_directory/bad-host" aarch64-w64-mingw32; then
	printf 'vdpm bundle for a different host was accepted\n' >&2
	exit 1
fi

unix_host=x86_64-linux-gnu
unix_root="$temporary_directory/unix-input/vdpm-test-$unix_host"
mkdir -p "$unix_root/bin/include" "$unix_root/libexec/vdpm" "$unix_root/share/vdpm/licenses"
for relative_path in vdpm vdpm-channel; do
	printf '%s\n' "$relative_path" > "$unix_root/bin/$relative_path"
done
for relative_path in pacman pacman-conf; do
	printf '%s\n' "$relative_path" > "$unix_root/libexec/vdpm/$relative_path"
done
printf 'refresh\n' > "$unix_root/bin/include/refresh-repositories.sh"
printf 'notices\n' > "$unix_root/share/vdpm/THIRD_PARTY_NOTICES.md"
printf 'license\n' > "$unix_root/share/vdpm/licenses/vdpm-LGPL-2.1.txt"
printf 'license\n' > "$unix_root/share/vdpm/licenses/pacman-GPL-2.0.txt"
printf 'schema_version=1\nhost=%s\n' "$unix_host" > \
	"$unix_root/share/vdpm/release-info.txt"
unix_bundle="$temporary_directory/vdpm-unix.tar.bz2"
tar -cjf "$unix_bundle" -C "$temporary_directory/unix-input" \
	"$(basename "$unix_root")"
if command -v sha256sum >/dev/null; then
	unix_digest=$(sha256sum "$unix_bundle")
else
	unix_digest=$(shasum -a 256 "$unix_bundle")
fi
unix_digest=${unix_digest%% *}
unix_sdk="$temporary_directory/unix-sdk"
"$repository_root/scripts/install-vdpm-bundle.sh" \
	"$unix_bundle" "$unix_digest" "$unix_sdk" "$unix_host"
test -f "$unix_sdk/bin/vdpm"
test -f "$unix_sdk/libexec/vdpm/pacman"
test -f "$unix_sdk/bin/vdpm-channel"
test -f "$unix_sdk/bin/include/refresh-repositories.sh"

toolchain="$temporary_directory/windows-toolchain.cmake"
cat > "$toolchain" <<EOF
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_C_COMPILER /usr/bin/cc)
set(CMAKE_CXX_COMPILER /usr/bin/c++)
set(CMAKE_C_COMPILER_FORCED TRUE)
set(CMAKE_CXX_COMPILER_FORCED TRUE)
set(CMAKE_RC_COMPILER /usr/bin/true)
set(CMAKE_EXE_LINKER_FLAGS "-static")
EOF
configure="$temporary_directory/configure"
# The staged build refuses a toolchain configure without a stage-1 SDK.
stage1_args=()
if [[ -n ${VITASDK_STAGE1_DIR:-} ]]; then
	stage1_args=(-DVITASDK_STAGE1_DIR="$VITASDK_STAGE1_DIR")
fi
cmake -S "$repository_root" -B "$configure" \
	-DCMAKE_TOOLCHAIN_FILE="$toolchain" \
	"${stage1_args[@]}" \
	-DBUILD_PACMAN_CLIENT=ON \
	-DVDPM_BUNDLE="$bundle" \
	-DVDPM_BUNDLE_SHA256="$digest" >/dev/null
host_zlib_config="$configure/zlib_host-prefix/tmp/zlib_host-cfgcmd.txt"
test -f "$host_zlib_config"
# A staged cross configure imports every build-machine artifact, so no
# *_build project may exist for target flags to leak into.
if compgen -G "$configure/*_build-prefix" >/dev/null; then
	printf 'build-machine dependency projects reappeared in a staged cross configure\n' >&2
	exit 1
fi
grep -Fq -- '-DCMAKE_EXE_LINKER_FLAGS=-static' "$host_zlib_config"
cmake --build "$configure" --target vdpm >/dev/null
test -f "$configure/vitasdk/bin/vdpm.exe"
test -f "$configure/vitasdk/share/vdpm/msys/usr/bin/pacman.exe"
test -f "$configure/vitasdk/share/vdpm/msys/usr/bin/vdpm-channel.exe"
test -f "$configure/vitasdk/share/vdpm/msys/usr/bin/msys-2.0.dll"

printf 'vdpm release bundle incorporation contract passed\n'
