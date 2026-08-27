#!/usr/bin/env bash
#
# Splice the softfp ABI shims (softfp-shim/wrappers/*.S, already assembled to
# *.o) into the stub archives vita-headers just installed, for the 23
# functions listed in softfp-shim/functions.tsv (see PLAN-softfp.md, "Fase 1
# - los 23 shims de serie").
#
# For each function this renames the real stub object's exported symbol to
# __vita_softfp_target_<name> (objcopy --redefine-sym) and adds the matching
# wrapper object as a new archive member under the original name. A static
# archive resolves symbols through its member index, not by member order, so
# after the rename there is exactly one provider of <name> left in the
# archive and no link-order dependency is introduced -- packages keep linking
# -lSceGxm_stub, -lScePvf_stub, etc. exactly as before.

set -euo pipefail

if [[ $# -ne 5 ]]; then
	printf 'usage: %s <lib-dir> <ar> <objcopy> <wrapper-obj-dir> <functions.tsv>\n' "$0" >&2
	exit 2
fi

lib_dir=$1
ar=$2
objcopy=$3
wrapper_dir=$4
functions_tsv=$5

[[ -d $lib_dir ]] || { printf 'lib dir not found: %s\n' "$lib_dir" >&2; exit 1; }

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

patch_archive() {
	local archive=$1 name=$2
	[[ -f $archive ]] || return 0

	local member
	member=$("$ar" t "$archive" | grep -E "_${name}\.(o|wo)\$" || true)
	if [[ -z $member ]]; then
		printf 'symbol %s not found in %s\n' "$name" "$archive" >&2
		exit 1
	fi

	local extract_dir="$work_dir/$(basename "$archive")-$name"
	mkdir -p "$extract_dir"
	(cd "$extract_dir" && "$ar" x "$archive" "$member")
	"$objcopy" --redefine-sym "${name}=__vita_softfp_target_${name}" \
		"$extract_dir/$member"

	"$ar" r "$archive" "$extract_dir/$member"
	"$ar" r "$archive" "$wrapper_dir/$name.o"
	"$ar" s "$archive"
}

while IFS=$'\t' read -r name header module; do
	[[ -n $name ]] || continue
	[[ -f "$wrapper_dir/$name.o" ]] || {
		printf 'wrapper object not found: %s/%s.o\n' "$wrapper_dir" "$name" >&2
		exit 1
	}
	patch_archive "$lib_dir/lib${module}_stub.a" "$name"
	patch_archive "$lib_dir/lib${module}_stub_weak.a" "$name"
done < "$functions_tsv"
