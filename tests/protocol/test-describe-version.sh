#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/vitasdk-describe-version.XXXXXXXX")
cleanup() { rm -rf -- "$temporary_root"; }
trap cleanup EXIT

describe() {
	python3 "$repository_root/scripts/describe.py" "$@"
}

field() {
	python3 -c 'import json, sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"
}

vercmp() {
	python3 "$repository_root/scripts/vercmp.py" "$1" "$2"
}

cd "$repository_root"
head_rev=$(git rev-parse HEAD)

# Nightly version derivation is deterministic.
version_a=$(describe --profile vita --revision "$head_rev" | field version)
version_b=$(describe --profile vita --revision "$head_rev" | field version)
[[ $version_a == "$version_b" ]] || {
	printf 'nightly version is not deterministic for the same revision\n' >&2
	exit 1
}

# The date-led scheme must outrank published run-number versions like 0.588.1.
[[ $(vercmp 0.588.1 "$version_a") == -1 ]] || {
	printf 'vercmp(0.588.1, %s) did not treat the new version as an upgrade\n' "$version_a" >&2
	exit 1
}

# The walkable range starts where describe's own files were introduced, not history's root.
introduced=$(git log --first-parent --format=%H --diff-filter=A -- cmake/Profiles.cmake | tail -1)
range_count=$(git rev-list --first-parent --count "${introduced}~1..$head_rev")
(( range_count >= 2 )) || {
	printf 'not enough describe-capable history yet to test monotonicity (%s commits)\n' \
		"$range_count" >&2
	exit 1
}

previous_version=
previous_rev=
while read -r rev; do
	version=$(describe --profile vita --revision "$rev" | field version)
	if [[ -n $previous_version ]]; then
		[[ $(vercmp "$previous_version" "$version") == -1 ]] || {
			printf '%s (%s) does not precede %s (%s) under vercmp\n' \
				"$previous_version" "$previous_rev" "$version" "$rev" >&2
			exit 1
		}
	fi
	previous_version=$version
	previous_rev=$rev
done < <(git rev-list --first-parent "${introduced}~1..$head_rev" | tac)

# A committed VERSION file bypasses the nightly monotonicity gate entirely.
clone="$temporary_root/clone"
git clone --quiet "$repository_root" "$clone"
git -C "$clone" config user.email describe-tests@ci.invalid
git -C "$clone" config user.name "describe tests"
cd "$clone"
printf '2026.08.0\n' > VERSION
git add VERSION
git commit -aq -m 'test: declare a stable version'
stable_rev=$(git rev-parse HEAD)

stable_version=$(describe --profile vita --revision "$stable_rev" --previous-version 999.999.999 | field version)
[[ $stable_version == 2026.08.0 ]] || {
	printf 'stable declaration was not used verbatim: got %s\n' "$stable_version" >&2
	exit 1
}

printf 'describe version derivation contract tests passed\n'
