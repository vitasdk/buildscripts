#!/usr/bin/env bash
#
# Generate softfp-shim/wrappers/*.S from the vita-headers this build just
# installed, assemble them, and splice them into every stub archive they
# touch, in every given lib dir. See patch-softfp-stub-archives.sh for what
# "splice" means; generation is cheap enough (a handful of regex passes over
# a few headers) to redo on every softfp build rather than trust a checked-in
# copy to still match vita-headers -- see softfp-shim/README.md.

set -euo pipefail

if [[ $# -lt 6 ]]; then
	printf 'usage: %s <cc> <ar> <objcopy> <shim-dir> <vita-headers-include-dir> <lib-dir>...\n' "$0" >&2
	exit 2
fi

cc=$1
ar=$2
objcopy=$3
shim_dir=$4
headers_dir=$5
shift 5

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

python3 "$shim_dir/generate.py" "$headers_dir" --out "$work_dir/wrappers"

for src in "$work_dir"/wrappers/*.S; do
	name=$(basename "$src" .S)
	"$cc" -c -mfpu=neon -mfloat-abi=softfp "$src" -o "$work_dir/$name.o"
done

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for lib_dir in "$@"; do
	"$script_dir/patch-softfp-stub-archives.sh" "$lib_dir" "$ar" "$objcopy" \
		"$work_dir" "$shim_dir/functions.tsv"
done
