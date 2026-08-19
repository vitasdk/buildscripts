#!/usr/bin/env bash
#
# Assemble softfp-shim/wrappers/*.S and splice them into every stub archive
# they touch, in every given lib dir. See patch-softfp-stub-archives.sh for
# what "splice" means; this just does the assembling and calls it once per
# lib dir (vita-headers installs its stub archives into two places -- the
# final SDK prefix and the toolchain's own build tree -- so both need it).

set -euo pipefail

if [[ $# -lt 5 ]]; then
	printf 'usage: %s <cc> <ar> <objcopy> <shim-dir> <lib-dir>...\n' "$0" >&2
	exit 2
fi

cc=$1
ar=$2
objcopy=$3
shim_dir=$4
shift 4

obj_dir=$(mktemp -d)
trap 'rm -rf "$obj_dir"' EXIT

for src in "$shim_dir"/wrappers/*.S; do
	name=$(basename "$src" .S)
	"$cc" -c -mfpu=neon -mfloat-abi=softfp "$src" -o "$obj_dir/$name.o"
done

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for lib_dir in "$@"; do
	"$script_dir/patch-softfp-stub-archives.sh" "$lib_dir" "$ar" "$objcopy" \
		"$obj_dir" "$shim_dir/functions.tsv"
done
