#!/usr/bin/env bash

set -euo pipefail

if (( $# != 4 )); then
	printf 'usage: %s <bundle.tar.bz2> <sha256> <sdk-root> <host-triplet>\n' "$0" >&2
	exit 2
fi

bundle=$1
expected=$2
sdk_root=$3
host=$4
[[ -f $bundle && ! -L $bundle ]] || exit 1
[[ $sdk_root == /* && $sdk_root != / ]] || exit 1
[[ $host =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || exit 1
[[ $expected =~ ^[0-9a-f]{64}$ ]] || exit 1
if command -v sha256sum >/dev/null; then
	actual=$(sha256sum "$bundle")
else
	actual=$(shasum -a 256 "$bundle")
fi
[[ ${actual%% *} == "$expected" ]] || {
	printf 'vdpm bundle hash mismatch\n' >&2
	exit 1
}

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/buildscripts-vdpm.XXXXXXXX")
cleanup() { rm -rf -- "$temporary_directory"; }
trap cleanup EXIT
while IFS= read -r entry; do
	case $entry in
		/*|../*|*/../*|*/..)
			printf 'vdpm bundle contains an unsafe path: %s\n' "$entry" >&2
			exit 1
			;;
	esac
done < <(tar -tjf "$bundle")
tar -xjf "$bundle" -C "$temporary_directory"
root_count=$(find "$temporary_directory" -mindepth 1 -maxdepth 1 -type d | wc -l)
(( root_count == 1 )) || exit 1
root=$(find "$temporary_directory" -mindepth 1 -maxdepth 1 -type d -print -quit)
grep -Fqx "host=$host" "$root/share/vdpm/release-info.txt"
test -f "$root/bin/vdpm.exe"
test -f "$root/usr/bin/pacman.exe"
test -f "$root/usr/bin/msys-2.0.dll"
mkdir -p "$sdk_root"
cp -a "$root/." "$sdk_root/"
