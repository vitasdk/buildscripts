#!/usr/bin/env bash
# Which hosts get their output verified, and how it is run.
#
# build-host.sh used to ask "is this native?", which skipped the toolchain
# contract and the bootstrap smoke test for every cross. That is right for a
# canadian cross to Windows or FreeBSD and wrong for Apple: an arm64 Mac runs
# x86_64 Mach-O through Rosetta, so the machine that cross-builds the Intel
# SDK is the one that can check it. Getting this wrong is silent -- the host
# publishes either way, just unverified.

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
script="$repository_root/scripts/ci/build-host.sh"

failures=0

# host_runner() reads $host and $build_host from the script's scope, so it is
# exercised the way the script calls it rather than through the CLI, which
# would need a whole toolchain to reach the same line.
runner_for()
{
	host=$1 build_host=$2 bash -c '
		host=$host
		build_host=$build_host
		'"$(sed -n '/^host_runner()/,/^}/p' "$script")"'
		if runner=$(host_runner); then
			printf "runs:%s" "$runner"
		else
			printf "cannot"
		fi
	'
}

check()
{
	description=$1
	actual=$(runner_for "$2" "$3")
	if [[ $actual != "$4" ]]; then
		printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' \
			"$description" "$4" "$actual" >&2
		failures=$((failures + 1))
	fi
}

# Native: runs directly, no launcher.
check "a native host runs its own output" \
	x86_64-linux-gnu "" "runs:"
check "a native Mac runs its own output" \
	arm64-apple-darwin "" "runs:"

# The case this exists for.
check "an arm64 Mac runs the Intel SDK it cross-built" \
	x86_64-apple-darwin arm64-apple-darwin "runs:arch -x86_64"

# The cases where the old comment was right and must stay right.
check "a Linux box cannot run Windows binaries" \
	x86_64-w64-mingw32 x86_64-linux-gnu "cannot"
check "a Linux box cannot run FreeBSD binaries" \
	x86_64-unknown-freebsd x86_64-linux-gnu "cannot"
check "a Linux box cannot run the Intel Mac SDK either" \
	x86_64-apple-darwin x86_64-linux-gnu "cannot"

# Rosetta goes one way only: an Intel Mac does not run arm64.
check "an Intel Mac cannot run an arm64 Mac SDK" \
	arm64-apple-darwin x86_64-apple-darwin "cannot"

# Which packaged hosts this script cannot run, pinned so that adding one
# passes somebody's eyes. Windows is on the list and is still verified: a
# dedicated job smoke-tests its bootstrap on a real Windows runner. The two
# FreeBSD hosts are on it and are verified nowhere, which is a gap this test
# records rather than fixes -- closing it needs a FreeBSD VM, not Rosetta.
unverified=$(python3 - "$repository_root/cmake/hosts.json" <<'PYTHON'
import json, sys
hosts = json.load(open(sys.argv[1]))["hosts"]
out = []
for h in hosts:
    if not h["packaged"]:
        continue
    build_host = h.get("build_host")
    if not build_host:
        continue
    if h["name"] == "x86_64-apple-darwin" and build_host == "arm64-apple-darwin":
        continue
    out.append(h["name"])
print(" ".join(sorted(out)))
PYTHON
)
expected="aarch64-unknown-freebsd x86_64-unknown-freebsd x86_64-w64-mingw32"
if [[ $unverified != "$expected" ]]; then
	printf 'FAIL: the set of hosts this script cannot run changed\n  expected: %s\n  actual:   %s\n' \
		"$expected" "$unverified" >&2
	failures=$((failures + 1))
fi

if (( failures )); then
	printf '%d host-runner check(s) failed\n' "$failures" >&2
	exit 1
fi

printf 'host runner contract tests passed\n'
