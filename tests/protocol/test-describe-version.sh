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

# The same file describe reads to decide a version is declared.
VERSION_PATH=VERSION

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

# Reasons the walk has nothing to walk. Neither is a failure, and neither
# stops the checks below it: skipping used to exit, which took the stable
# declaration with it on exactly the branches that have one.
skip_walk=""
if git cat-file -e "$head_rev:$VERSION_PATH" 2>/dev/null; then
	# Every commit on a release branch answers with what VERSION says, so
	# there is no derived version here to be monotonic. The derivation and
	# its guards are covered by the synthetic-history test, which builds
	# the history it needs instead of borrowing this one.
	skip_walk="$head_rev declares a version"
elif (( range_count < 2 )); then
	# A PR merge ref's first parent is master, where describe's files do not
	# exist yet, so the walkable range collapses to the merge commit alone.
	skip_walk="$range_count describe-capable commit(s) on the first-parent line"
fi

chain=()
if [[ -n $skip_walk ]]; then
	printf 'skipping the real-history walk: %s\n' "$skip_walk"
else
	while read -r rev; do
		chain+=("$rev")
	done < <(git rev-list --first-parent "${introduced}~1..$head_rev")
fi

previous_version=
previous_rev=
for (( i = ${#chain[@]} - 1; i >= 0; i-- )); do
	rev=${chain[i]}
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
done

# A committed VERSION file is used verbatim, not derived from the history.
clone="$temporary_root/clone"
git clone --quiet "$repository_root" "$clone"
git -C "$clone" config user.email describe-tests@ci.invalid
git -C "$clone" config user.name "describe tests"
cd "$clone"
printf '2026.08.0\n' > VERSION
git add VERSION
git commit -aq -m 'test: declare a stable version'
stable_rev=$(git rev-parse HEAD)

stable_version=$(describe --profile vita --revision "$stable_rev" | field version)
[[ $stable_version == 2026.08.0 ]] || {
	printf 'stable declaration was not used verbatim: got %s\n' "$stable_version" >&2
	exit 1
}

# The series is what the publisher points at a new core. Getting it from the
# lock is what stops a patch of 2026.08 being announced as a nightly, which
# would drag every nightly user onto the series' older target runtime.
stable_series=$(describe --profile vita --revision "$stable_rev" | field series)
[[ $stable_series == 2026.08 ]] || {
	printf 'declared version did not yield its series: got %s\n' "$stable_series" >&2
	exit 1
}

printf '2026.08.1\n' > VERSION
git commit -aq -m 'test: declare a patch of the same series'
patch_series=$(describe --profile vita --revision "$(git rev-parse HEAD)" | field series)
[[ $patch_series == 2026.08 ]] || {
	printf 'a patch did not stay in its series: got %s\n' "$patch_series" >&2
	exit 1
}

# A nightly has no series at all: it is a channel, not a release line.
git rm -q VERSION
git commit -aq -m 'test: back to a derived version'
nightly_series=$(describe --profile vita --revision "$(git rev-parse HEAD)" | field series)
[[ $nightly_series == None ]] || {
	printf 'a derived version claimed a series: got %s\n' "$nightly_series" >&2
	exit 1
}

printf 'nonsense\n' > VERSION
git add VERSION
git commit -aq -m 'test: declare a version with no patch level'
if output=$(describe --profile vita --revision "$(git rev-parse HEAD)" 2>&1); then
	printf 'describe accepted a declared version that is not <series>.<patch>\n' >&2
	exit 1
fi
grep -qi 'series' <<< "$output" || {
	printf 'describe did not say what was wrong with it: %s\n' "$output" >&2
	exit 1
}

printf 'describe version derivation contract tests passed\n'
