#!/usr/bin/env bash
# The lock and the build recipe are two halves of one decision.
#
# hosts.json says whether a host is cross-built; the case block in
# build-host.sh says how. Nothing tied them together, so #161 made
# x86_64-apple-darwin native in both and db4d1a593 made it a cross again in
# the lock alone: the job then built an arm64 SDK, published it under the
# Intel name, and stayed green until the bootstrap smoke test, 18 minutes in.

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
script="$repository_root/scripts/ci/build-host.sh"

failures=0

# The case block is run as the script runs it, not re-implemented here. The
# setup scripts it calls are stubbed by name from a scratch directory: what
# is under test is the dispatch, not what a cross environment costs to build.
stubs=$(mktemp -d)
trap 'rm -rf "$stubs"' EXIT
mkdir -p "$stubs/scripts"
for stub in setup-macos-cross.sh setup-freebsd-cross.sh; do
	printf '#!/bin/sh\nexit 0\n' >"$stubs/scripts/$stub"
	chmod +x "$stubs/scripts/$stub"
done

toolchain_file_for()
{
	(
		cd "$stubs" || exit 1
		host=$1 repo_root=$repository_root bash -c '
			set -euo pipefail
			host=$host
			repo_root=$repo_root
			install_dependencies() { :; }
			'"$(sed -n '/^extra_cmake_args=()/,/^esac/p' "$script")"'
			printf "%s" "${extra_cmake_args[*]:-}"
		'
	)
}

check()
{
	local host=$1 build_host=$2 args status expected
	args=$(toolchain_file_for "$host") && status=0 || status=$?
	if ((status != 0)); then
		printf 'FAIL: %s has no build recipe in build-host.sh\n' "$host" >&2
		failures=$((failures + 1))
		return
	fi
	if [[ -n $build_host ]]; then
		expected="-DCMAKE_TOOLCHAIN_FILE=$repository_root/cmake/toolchains/$host.cmake"
		if [[ $args != *"$expected"* ]]; then
			printf 'FAIL: %s is cross-built from %s but its recipe does not use %s.cmake\n  recipe: %s\n' \
				"$host" "$build_host" "$host" "${args:-<none>}" >&2
			failures=$((failures + 1))
		fi
		if [[ ! -f $repository_root/cmake/toolchains/$host.cmake ]]; then
			printf 'FAIL: %s names a toolchain file that does not exist\n' "$host" >&2
			failures=$((failures + 1))
		fi
	elif [[ $args == *CMAKE_TOOLCHAIN_FILE* ]]; then
		printf 'FAIL: %s builds natively in the lock but its recipe cross-compiles\n  recipe: %s\n' \
			"$host" "$args" >&2
		failures=$((failures + 1))
	fi
}

# musl hosts never reach the case block: they build inside Alpine, where the
# build is native, and build-host.sh dispatches them before it.
while read -r host build_host; do
	check "$host" "$build_host"
done < <(python3 - "$repository_root/cmake/hosts.json" <<'PYTHON'
import json, sys

seen = set()
for host in json.load(open(sys.argv[1]))["hosts"]:
    name = host["name"]
    if name.endswith("-linux-musl") or name in seen:
        continue
    seen.add(name)
    print(name, host.get("build_host", ""))
PYTHON
)

if ((failures)); then
	printf '%d cross-host recipe check(s) failed\n' "$failures" >&2
	exit 1
fi

printf 'cross host recipe tests passed\n'
