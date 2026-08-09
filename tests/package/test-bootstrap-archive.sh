#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/buildscripts-bootstrap.XXXXXXXX")
cleanup() { rm -rf -- "$temporary_directory"; }
trap cleanup EXIT

sdk="$temporary_directory/sdk"
mkdir -p "$sdk/bin/include" "$sdk/etc" "$sdk/share/vdpm/licenses"
for file in vdpm arm-vita-eabi-gcc pacman vdpm-channel; do
	printf '%s\n' "$file" > "$sdk/bin/$file"
done
printf 'refresh\n' > "$sdk/bin/include/refresh-repositories.sh"
printf '[options]\nArchitecture = x86_64-linux-gnu vita\n' > "$sdk/etc/pacman.conf"
printf 'revision\n' > "$sdk/version_info.txt"
printf 'notices\n' > "$sdk/share/vdpm/THIRD_PARTY_NOTICES.md"
printf 'vdpm license\n' > "$sdk/share/vdpm/licenses/vdpm-LGPL-2.1.txt"
printf 'pacman license\n' > "$sdk/share/vdpm/licenses/pacman-GPL-2.0.txt"

for output in one two; do
	"$repository_root/scripts/create-bootstrap-archive.sh" \
		"$sdk" "$temporary_directory/$output" x86_64-linux-gnu 1700000000
done
archive=vitasdk-bootstrap-x86_64-linux-gnu.tar.bz2
cmp "$temporary_directory/one/$archive" "$temporary_directory/two/$archive"
entries=$(tar -tjf "$temporary_directory/one/$archive")
grep -qx 'vitasdk/bin/vdpm' <<< "$entries"
grep -qx 'vitasdk/bin/pacman' <<< "$entries"
grep -qx 'vitasdk/etc/pacman.conf' <<< "$entries"
grep -qx 'vitasdk/version_info.txt' <<< "$entries"
grep -qx 'vitasdk/share/vdpm/THIRD_PARTY_NOTICES.md' <<< "$entries"

printf 'reproducible VitaSDK bootstrap archive contract passed\n'
