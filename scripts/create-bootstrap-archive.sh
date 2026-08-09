#!/usr/bin/env bash

set -euo pipefail

if (( $# != 4 )); then
	printf 'usage: %s <sdk-root> <output-directory> <host-triplet> <source-date-epoch>\n' "$0" >&2
	exit 2
fi

sdk_root=$1
output_directory=$2
host=$3
source_date_epoch=$4
[[ -d $sdk_root && $sdk_root == /* && $sdk_root != / ]] || exit 1
[[ $host =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || exit 1
[[ $source_date_epoch =~ ^[0-9]+$ ]] || exit 1

required=(version_info.txt etc/pacman.conf share/vdpm/THIRD_PARTY_NOTICES.md
	share/vdpm/licenses/vdpm-LGPL-2.1.txt
	share/vdpm/licenses/pacman-GPL-2.0.txt)
case $host in
	*-w64-mingw32)
		required+=(bin/vdpm.exe bin/arm-vita-eabi-gcc.exe \
			usr/bin/pacman.exe usr/bin/vdpm-channel.exe usr/bin/msys-2.0.dll \
			share/vdpm/refresh-repositories.ps1)
		;;
	*)
		required+=(bin/vdpm bin/arm-vita-eabi-gcc bin/pacman bin/vdpm-channel \
			bin/include/refresh-repositories.sh)
		;;
esac
for relative_path in "${required[@]}"; do
	[[ -e $sdk_root/$relative_path ]] || {
		printf 'bootstrap SDK is missing %s\n' "$relative_path" >&2
		exit 1
	}
done

mkdir -p "$output_directory"
output_directory=$(cd "$output_directory" && pwd -P)
archive="$output_directory/vitasdk-bootstrap-$host.tar.bz2"
checksum="$archive.sha256"
[[ ! -e $archive && ! -e $checksum ]] || exit 1
temporary_directory=$(mktemp -d "$output_directory/.bootstrap.XXXXXXXX")
cleanup() { rm -rf -- "$temporary_directory"; }
trap cleanup EXIT
mkdir "$temporary_directory/vitasdk"
cp -a "$sdk_root/." "$temporary_directory/vitasdk/"

if touch -h -d "@$source_date_epoch" "$temporary_directory/vitasdk" 2>/dev/null; then
	find "$temporary_directory/vitasdk" -exec touch -h -d "@$source_date_epoch" {} +
else
	timestamp=$(date -r "$source_date_epoch" -u '+%Y%m%d%H%M.%S')
	find "$temporary_directory/vitasdk" -exec touch -h -t "$timestamp" {} +
fi
(
	cd "$temporary_directory"
	find vitasdk -print | LC_ALL=C sort > archive.list
	if tar --version 2>/dev/null | grep -q 'GNU tar'; then
		tar --no-recursion --sort=name --mtime="@$source_date_epoch" \
			--owner=0 --group=0 --numeric-owner -cjf "$archive" -T archive.list
	else
		COPYFILE_DISABLE=1 tar --no-recursion --uid 0 --gid 0 \
			--uname root --gname root -cjf "$archive" -T archive.list
	fi
)
if command -v sha256sum >/dev/null; then
	(cd "$output_directory" && sha256sum "$(basename "$archive")") > "$checksum"
else
	digest=$(shasum -a 256 "$archive")
	printf '%s  %s\n' "${digest%% *}" "$(basename "$archive")" > "$checksum"
fi
printf '%s\n' "$archive"
