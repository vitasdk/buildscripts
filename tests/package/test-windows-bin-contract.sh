#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/vitasdk-windows-bin-package.XXXXXXXX")
sdk_root="$temporary_root/sdk"

cleanup() {
	rm -rf -- "$temporary_root"
}
trap cleanup EXIT

mkdir -p "$sdk_root/bin/libmakepkg" "$sdk_root/arm-vita-eabi/lib" \
	"$sdk_root/share/licenses/pkgconf" "$sdk_root/share/vdpm/licenses" \
	"$sdk_root/share/vdpm/msys/usr/bin"

for executable in arm-vita-eabi-gcc.exe pkgconf.exe arm-vita-eabi-pkg-config.exe; do
	printf 'MZ%s\n' "$executable" > "$sdk_root/bin/$executable"
done
printf 'MZvdpm\n' > "$sdk_root/bin/vdpm.exe"
printf 'CARCH="vita"\n' > "$sdk_root/bin/makepkg.conf"
printf '#!/usr/bin/env sh\n' > "$sdk_root/bin/vita-makepkg"
printf '#!/usr/bin/env sh\n' > "$sdk_root/bin/vitasdk-update"
printf '#!/usr/bin/env sh\n' > "$sdk_root/bin/arm-vita-eabi-gdb-add-index"
printf 'nested helper\n' > "$sdk_root/bin/libmakepkg/internal-helper"
printf 'archive\n' > "$sdk_root/arm-vita-eabi/lib/libfixture.a"
printf 'source=fixture\nworld vita (float-abi=hard)\n' > "$sdk_root/version_info.txt"
printf 'pkgconf license\n' > "$sdk_root/share/licenses/pkgconf/COPYING"
printf 'notices\n' > "$sdk_root/share/vdpm/THIRD_PARTY_NOTICES.md"
printf 'vdpm license\n' > "$sdk_root/share/vdpm/licenses/vdpm-LGPL-2.1.txt"
printf 'pacman license\n' > "$sdk_root/share/vdpm/licenses/pacman-GPL-2.0.txt"
printf 'refresh\n' > "$sdk_root/share/vdpm/refresh-repositories.ps1"
printf 'version=0.1.0\nhost=x86_64-w64-mingw32\n' > "$sdk_root/share/vdpm/release-info.txt"
for runtime in pacman.exe vdpm-channel.exe msys-2.0.dll; do
	printf 'MZ%s\n' "$runtime" > "$sdk_root/share/vdpm/msys/usr/bin/$runtime"
done

SOURCE_DATE_EPOCH=1700000000 \
	"$repository_root/scripts/create-core-package.sh" \
	"$sdk_root" "$temporary_root/valid" x86_64-w64-mingw32 \
	0.1 0123456789abcdef >/dev/null

core_package="$temporary_root/valid/vitasdk-core-0.1-1-x86_64-w64-mingw32.pkg.tar.xz"
core_entries=$(bsdtar -tf "$core_package")
for path in bin/makepkg.conf bin/vita-makepkg bin/vitasdk-update \
		bin/arm-vita-eabi-gdb-add-index bin/libmakepkg/internal-helper; do
	grep -Fqx "$path" <<< "$core_entries" || {
		printf 'the Windows core package lost %s\n' "$path" >&2
		exit 1
	}
done

expect_rejected() {
	local offender=$1 contents=$2
	local invalid_sdk="$temporary_root/sdk-$offender"
	local output="$temporary_root/output-$offender" log="$temporary_root/$offender.log"
	cp -a "$sdk_root" "$invalid_sdk"
	printf '%s\n' "$contents" > "$invalid_sdk/bin/$offender"
	if SOURCE_DATE_EPOCH=1700000000 \
		"$repository_root/scripts/create-core-package.sh" \
		"$invalid_sdk" "$output" x86_64-w64-mingw32 \
		0.1 0123456789abcdef >"$log" 2>&1; then
		printf 'the package validator accepted bin/%s\n' "$offender" >&2
		exit 1
	fi
	grep -Fq "$offender" "$log" || {
		printf 'the package rejection did not name bin/%s\n' "$offender" >&2
		cat "$log" >&2
		exit 1
	}
}

expect_rejected unknown-script '#!/usr/bin/env sh'
expect_rejected unknown-data 'not executable data'

printf 'Windows package bin contract checks passed\n'
