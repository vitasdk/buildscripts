#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/vitasdk-describe-lock.XXXXXXXX")
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
base_rev=$(git rev-parse HEAD)

# Determinism: same revision, same profile, byte-identical lock.
first_run=$(describe --profile vita --revision "$base_rev")
second_run=$(describe --profile vita --revision "$base_rev")
[[ $first_run == "$second_run" ]] || {
	printf 'describe is not deterministic for the same revision and profile\n' >&2
	exit 1
}
base_build_id=$(field build_id <<< "$first_run")

# Changing the profile changes build_id, same revision.
softfp_build_id=$(describe --profile vita_softfp --revision "$base_rev" | field build_id)
[[ $base_build_id != "$softfp_build_id" ]] || {
	printf 'build_id did not change when the profile changed\n' >&2
	exit 1
}

# Changing the revision changes build_id, same profile.
python3 - <<'PYEOF'
import re
path = "cmake/Components.cmake"
text = open(path).read()
text = re.sub(r'(set\(NEWLIB_TAG )[0-9a-f]{40}', r'\g<1>' + '1' * 40, text)
open(path, "w").write(text)
PYEOF
git commit -aq -m 'test: bump the newlib pin'
bumped_rev=$(git rev-parse HEAD)
bumped_build_id=$(describe --profile vita --revision "$bumped_rev" | field build_id)
[[ $base_build_id != "$bumped_build_id" ]] || {
	printf 'build_id did not change when the revision changed\n' >&2
	exit 1
}

# Unknown profile fails, naming the profile and the known list.
if output=$(describe --profile bogus --revision "$bumped_rev" 2>&1); then
	printf 'describe accepted an unknown profile\n' >&2
	exit 1
fi
grep -q 'bogus' <<< "$output" || {
	printf 'describe did not name the rejected profile: %s\n' "$output" >&2
	exit 1
}

# Malformed/missing pin data fails, naming what is missing.
python3 - <<'PYEOF'
import re
path = "cmake/Components.cmake"
text = open(path).read()
text = re.sub(r'set\(NEWLIB_TAG[^\n]*\n', '', text)
open(path, "w").write(text)
PYEOF
git commit -aq -m 'test: drop the newlib pin'
broken_rev=$(git rev-parse HEAD)
if output=$(describe --profile vita --revision "$broken_rev" 2>&1); then
	printf 'describe accepted a revision with a missing pin\n' >&2
	exit 1
fi
grep -qi 'newlib' <<< "$output" || {
	printf 'describe did not name the missing pin: %s\n' "$output" >&2
	exit 1
}

printf 'describe lock/build_id contract tests passed\n'
