#!/usr/bin/env bash
# Shared helpers for the reusable build workflow's entry-point scripts.

ci_sha256() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	else
		shasum -a 256 "$1" | awk '{print $1}'
	fi
}

ci_nproc() {
	if [[ $(uname -s) == Darwin ]]; then
		sysctl -n hw.logicalcpu
	else
		nproc
	fi
}

# Locates the root of an unpacked SDK/sysroot tree via its target payload.
ci_find_sdk_root() {
	local search_root=$1 marker
	marker=$(find "$search_root" -type f -path '*/arm-vita-eabi/lib/libc.a' | head -1)
	[[ -n $marker ]] || {
		printf 'no unpacked SDK found under %s\n' "$search_root" >&2
		return 1
	}
	dirname "$(dirname "$(dirname "$marker")")"
}

ci_unpack_sdk_artifact() {
	local artifact_dir=$1 destination=$2
	mkdir -p "$destination"
	local archive=""
	for candidate in "$artifact_dir"/*.tar.bz2; do
		[[ -f $candidate ]] && archive=$candidate && break
	done
	[[ -n $archive ]] || {
		printf 'no .tar.bz2 archive found in %s\n' "$artifact_dir" >&2
		return 1
	}
	tar -xjf "$archive" -C "$destination"
}

# Finds the artifact dir for a (stage, host name) pair; name_glob may be '*'.
# Stage is required: a lock may reuse one host name at several stages.
ci_find_stage_artifact() {
	local artifacts_dir=$1 stage=$2 name_glob=$3
	local candidate
	for candidate in "$artifacts_dir"/stage"$stage"-$name_glob; do
		[[ -d $candidate ]] && printf '%s\n' "$candidate" && return 0
	done
	return 1
}

# Echoes build_id plus produced filenames for the grouping job to read back.
ci_write_provenance() {
	local out_dir=$1 host=$2 build_id=$3
	shift 3
	python3 - "$out_dir/provenance.json" "$host" "$build_id" "$@" <<'PY'
import json
import sys

out_path, host, build_id, *artifacts = sys.argv[1:]
with open(out_path, "w", encoding="utf-8") as handle:
    json.dump(
        {"host": host, "build_id": build_id, "artifacts": artifacts},
        handle, indent=2, sort_keys=True,
    )
    handle.write("\n")
PY
}
