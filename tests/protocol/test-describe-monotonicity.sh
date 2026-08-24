#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/vitasdk-describe-mono.XXXXXXXX")
cleanup() { rm -rf -- "$temporary_root"; }
trap cleanup EXIT

clone="$temporary_root/clone"
git clone --quiet "$repository_root" "$clone"
git -C "$clone" config user.email describe-tests@ci.invalid
git -C "$clone" config user.name "describe tests"

describe() {
	python3 "$repository_root/scripts/describe.py" "$@"
}

field() {
	python3 -c 'import json, sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"
}

cd "$clone"

# describe fails when the candidate's committer date precedes its parent's.
parent_epoch=$(git log -1 --format=%ct HEAD)
skewed_epoch=$(( parent_epoch - 3600 ))
printf 'clock skew probe\n' >> README.md
GIT_AUTHOR_DATE="$skewed_epoch +0000" GIT_COMMITTER_DATE="$skewed_epoch +0000" \
	git commit -aq -m 'test: committed an hour before its own parent'
skewed_rev=$(git rev-parse HEAD)

if output=$(describe --profile vita --revision "$skewed_rev" 2>&1); then
	printf 'describe accepted a revision older than its first parent\n' >&2
	exit 1
fi
grep -qi 'first parent' <<< "$output" || {
	printf 'describe did not name the first-parent clock-skew guard: %s\n' "$output" >&2
	exit 1
}

# --previous-version: fails when the candidate does not exceed it, passes
# when it does. Roll back to a clean, non-skewed commit first.
git reset --hard --quiet HEAD^
clean_rev=$(git rev-parse HEAD)
version=$(describe --profile vita --revision "$clean_rev" | field version)

if output=$(describe --profile vita --revision "$clean_rev" --previous-version "$version" 2>&1); then
	printf 'describe accepted a candidate equal to the previous version\n' >&2
	exit 1
fi
grep -qi 'previous version' <<< "$output" || {
	printf 'describe did not name the previous-version guard: %s\n' "$output" >&2
	exit 1
}

if output=$(describe --profile vita --revision "$clean_rev" --previous-version "9.99999999.9999" 2>&1); then
	printf 'describe accepted a candidate that does not exceed a higher previous version\n' >&2
	exit 1
fi

describe --profile vita --revision "$clean_rev" --previous-version "0.1.1" > /dev/null || {
	printf 'describe rejected a candidate that genuinely exceeds the previous version\n' >&2
	exit 1
}

printf 'describe monotonicity guard contract tests passed\n'
