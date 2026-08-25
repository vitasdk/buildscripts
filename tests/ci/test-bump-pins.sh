#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/vitasdk-bump-pins.XXXXXXXX")
cleanup() { rm -rf -- "$temporary_root"; }
trap cleanup EXIT

work="$temporary_root/work"
mkdir -p "$work/cmake"
cp "$repository_root/cmake/Components.cmake" "$work/cmake/Components.cmake"
cp "$repository_root/cmake/pin-tracking.json" "$work/cmake/pin-tracking.json"

components="$work/cmake/Components.cmake"
tracking="$work/cmake/pin-tracking.json"

bump() {
	python3 "$repository_root/scripts/bump-pins.py" \
		--components "$components" --tracking "$tracking" "$@"
}

# The upstreams the bot follows, straight from the file under test: a
# component added to the config is exercised here without editing this test.
mapfile -t tracked < <(python3 - "$tracking" <<'PYEOF'
import json, sys
config = json.load(open(sys.argv[1]))
for name, entry in sorted(config["tracked"].items()):
    print(f"{name} {entry['branch']}")
PYEOF
)
[[ ${#tracked[@]} -ge 2 ]] || {
	printf 'the tracking config declares fewer than two components\n' >&2
	exit 1
}

overrides=()
declare -A upstream_of=()
for entry in "${tracked[@]}"; do
	read -r name branch <<< "$entry"
	upstream="$temporary_root/upstream/$name"
	mkdir -p "$upstream"
	git init --quiet --initial-branch "$branch" "$upstream"
	git -C "$upstream" config user.email bump-pins-tests@ci.invalid
	git -C "$upstream" config user.name "bump-pins tests"
	echo "first" > "$upstream/file"
	git -C "$upstream" add file
	git -C "$upstream" commit --quiet -m "first"
	upstream_of[$name]=$upstream
	overrides+=(--repository "$name=$upstream")
done

pin_of() {
	python3 - "$components" "$1" <<'PYEOF'
import re, sys
variable = sys.argv[2].upper().replace("-", "_")
text = open(sys.argv[1]).read()
match = re.search(r"set\(\s*" + variable + r"_TAG\s+(\S+)", text)
print(match.group(1) if match else "")
PYEOF
}

# Everything moves once, to exactly what the upstream branches hold.
output=$(bump "${overrides[@]}")
grep -q "bump-pins: ${#tracked[@]} pin(s) moved" <<< "$output" || {
	printf 'the first bump did not move every tracked pin: %s\n' "$output" >&2
	exit 1
}
for entry in "${tracked[@]}"; do
	read -r name _ <<< "$entry"
	expected=$(git -C "${upstream_of[$name]}" rev-parse HEAD)
	[[ $(pin_of "$name") == "$expected" ]] || {
		printf 'pin of %s is not the upstream head\n' "$name" >&2
		exit 1
	}
done

# Convergence: nothing upstream moved, so the bot writes nothing. Its own
# push must never be a reason for the next run to commit again.
cp "$components" "$temporary_root/before-idle"
output=$(bump "${overrides[@]}" --message-file "$temporary_root/idle-message")
grep -q 'bump-pins: nothing moved' <<< "$output" || {
	printf 'an idle bump reported movement: %s\n' "$output" >&2
	exit 1
}
cmp -s "$components" "$temporary_root/before-idle" || {
	printf 'an idle bump rewrote Components.cmake\n' >&2
	exit 1
}
[[ ! -s "$temporary_root/idle-message" ]] || {
	printf 'an idle bump wrote a commit message\n' >&2
	exit 1
}

# One leaf moves: one pin changes, one line changes, and the message says
# which component it was.
read -r moved_name moved_branch <<< "${tracked[0]}"
moved_upstream=${upstream_of[$moved_name]}
echo "second" > "$moved_upstream/file"
git -C "$moved_upstream" commit --quiet -am "second"
moved_head=$(git -C "$moved_upstream" rev-parse HEAD)

cp "$components" "$temporary_root/before-one"
output=$(bump "${overrides[@]}" --message-file "$temporary_root/one-message")
grep -q 'bump-pins: 1 pin(s) moved' <<< "$output" || {
	printf 'moving one upstream did not move exactly one pin: %s\n' "$output" >&2
	exit 1
}
[[ $(pin_of "$moved_name") == "$moved_head" ]] || {
	printf 'pin of %s did not follow its upstream\n' "$moved_name" >&2
	exit 1
}
changed=$(diff "$temporary_root/before-one" "$components" | grep '^[<>]' || true)
[[ $(grep -c . <<< "$changed") -eq 2 ]] || {
	printf 'moving one pin changed more than one line:\n%s\n' "$changed" >&2
	exit 1
}
[[ $(grep -c '_TAG' <<< "$changed") -eq 2 ]] || {
	printf 'the bot changed something that is not a pin:\n%s\n' "$changed" >&2
	exit 1
}
grep -q "$moved_name" "$temporary_root/one-message" || {
	printf 'the commit message does not name %s\n' "$moved_name" >&2
	exit 1
}
grep -q "$moved_branch" "$temporary_root/one-message" || {
	printf 'the commit message does not name the branch followed\n' >&2
	exit 1
}

# A dry run reports what it would do and writes nothing.
echo "third" > "$moved_upstream/file"
git -C "$moved_upstream" commit --quiet -am "third"
cp "$components" "$temporary_root/before-dry"
output=$(bump "${overrides[@]}" --dry-run)
grep -q 'bump-pins: 1 pin(s) moved' <<< "$output" || {
	printf 'the dry run did not report the pending move: %s\n' "$output" >&2
	exit 1
}
cmp -s "$components" "$temporary_root/before-dry" || {
	printf 'the dry run rewrote Components.cmake\n' >&2
	exit 1
}

# The pins the config leaves alone stay exactly as the file declares them,
# and are never resolved: no override is given for any of them here.
for name in $(python3 -c 'import json,sys; print(" ".join(sorted(json.load(open(sys.argv[1]))["untracked"])))' "$tracking"); do
	before=$(python3 - "$repository_root/cmake/Components.cmake" "$name" <<'PYEOF'
import re, sys
variable = sys.argv[2].upper().replace("-", "_")
text = open(sys.argv[1]).read()
match = re.search(r"set\(\s*" + variable + r"_TAG\s+(\S+)", text)
print(match.group(1) if match else "")
PYEOF
	)
	[[ $(pin_of "$name") == "$before" ]] || {
		printf 'the bot moved the untracked pin %s\n' "$name" >&2
		exit 1
	}
done

# A branch that is not there fails loudly, naming what could not be resolved.
missing_branch_overrides=("${overrides[@]}")
missing="$temporary_root/upstream/missing"
git init --quiet --initial-branch nowhere "$missing"
git -C "$missing" config user.email bump-pins-tests@ci.invalid
git -C "$missing" config user.name "bump-pins tests"
echo x > "$missing/file"
git -C "$missing" add file
git -C "$missing" commit --quiet -m x
if output=$(bump "${missing_branch_overrides[@]}" --repository "$moved_name=$missing" 2>&1); then
	printf 'the bot accepted a branch that does not exist\n' >&2
	exit 1
fi
grep -q "$moved_branch" <<< "$output" || {
	printf 'the failure does not name the branch it could not resolve: %s\n' "$output" >&2
	exit 1
}

# A pin added to the build and to neither list stops the bot before it
# resolves anything, naming the component nobody decided about.
cp "$components" "$temporary_root/before-undeclared"
cat >> "$components" <<'CMAKEEOF'

set(SOMETHING_REPOSITORY https://github.com/vitasdk/something)
set(SOMETHING_TAG 0000000000000000000000000000000000000000)
CMAKEEOF
if output=$(bump "${overrides[@]}" 2>&1); then
	printf 'the bot ran with an undeclared pin\n' >&2
	exit 1
fi
grep -q 'something' <<< "$output" || {
	printf 'the failure does not name the undeclared pin: %s\n' "$output" >&2
	exit 1
}
cp "$temporary_root/before-undeclared" "$components"

# A tracked name that is not a pin at all is a typo, and says so.
python3 - "$tracking" <<'PYEOF'
import json, sys
config = json.load(open(sys.argv[1]))
config["tracked"]["bogus"] = {"branch": "master"}
json.dump(config, open(sys.argv[1], "w"), indent=2)
PYEOF
if output=$(bump "${overrides[@]}" 2>&1); then
	printf 'the bot ran with a tracked component that is not pinned\n' >&2
	exit 1
fi
grep -q 'bogus' <<< "$output" || {
	printf 'the failure does not name the unknown component: %s\n' "$output" >&2
	exit 1
}

printf 'bump-pins: all checks passed\n'
