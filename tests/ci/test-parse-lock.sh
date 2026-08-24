#!/usr/bin/env bash
# Contract tests for the reusable build workflow's schema gate
# (scripts/ci/parse-lock.py): the one piece of the shell that inspects the
# lock at all, so it is the one piece worth unit-testing directly.

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/buildscripts-parse-lock.XXXXXXXX")
cleanup() { rm -rf -- "$temporary_directory"; }
trap cleanup EXIT

run_parse() {
	local lock_json=$1 output_file="$temporary_directory/output-$RANDOM"
	: >"$output_file"
	LOCK_JSON=$lock_json GITHUB_OUTPUT="$output_file" \
		python3 "$repository_root/scripts/ci/parse-lock.py"
	printf '%s\n' "$output_file"
}

assert_fails() {
	local lock_json=$1 message=$2 output_file="$temporary_directory/output-$RANDOM"
	: >"$output_file"
	if LOCK_JSON=$lock_json GITHUB_OUTPUT="$output_file" \
		python3 "$repository_root/scripts/ci/parse-lock.py" 2>/dev/null; then
		printf '%s: unexpectedly succeeded\n' "$message" >&2
		exit 1
	fi
}

output_value() {
	local output_file=$1 name=$2
	awk -v name="$name" '
		!in_block && index($0, name "<<") == 1 {
			delim = substr($0, length(name) + 3)
			in_block = 1
			next
		}
		in_block && $0 == delim { in_block = 0; next }
		in_block { print }
	' "$output_file"
}

# x86_64-linux-gnu deliberately recurs at stage 1 (sysroot producer) and
# stage 2 (native SDK) -- matching the real describe hosts.json shape, not
# an invented pseudo-host name for stage 1.
good_lock='{
  "schema": 1,
  "build_id": "sha256:aaaa",
  "buildscripts_revision": "0123456789abcdef0123456789abcdef01234567",
  "profile": "vita",
  "version": "0.20260822.249",
  "hosts": [
    {"name": "x86_64-linux-gnu", "stage": 1, "runner": "ubuntu-24.04", "container": "ubuntu:20.04"},
    {"name": "x86_64-linux-gnu", "stage": 2, "runner": "ubuntu-24.04", "container": "ubuntu:20.04"},
    {"name": "x86_64-w64-mingw32", "stage": 3, "runner": "ubuntu-24.04", "container": null}
  ]
}'

# 1. A well-formed schema-1 lock is accepted and grouped by stage, and the
# same host name recurring at two stages is not treated as a duplicate.
output=$(run_parse "$good_lock")
[[ $(output_value "$output" schema) == 1 ]]
[[ $(output_value "$output" build_id) == 'sha256:aaaa' ]]
[[ $(output_value "$output" version) == '0.20260822.249' ]]
stage1=$(output_value "$output" stage1_hosts)
stage2=$(output_value "$output" stage2_hosts)
stage3=$(output_value "$output" stage3_hosts)
python3 -c "
import json, sys
stage1, stage2, stage3 = json.loads(sys.argv[1]), json.loads(sys.argv[2]), json.loads(sys.argv[3])
assert [h['name'] for h in stage1] == ['x86_64-linux-gnu'], stage1
assert [h['name'] for h in stage2] == ['x86_64-linux-gnu'], stage2
assert [h['name'] for h in stage3] == ['x86_64-w64-mingw32'], stage3
assert stage3[0]['container'] == '', stage3[0]
" "$stage1" "$stage2" "$stage3"

# 2. An unsupported schema fails loudly and does not silently misbuild.
assert_fails '{"schema": 2, "build_id": "x", "buildscripts_revision": "0123456789abcdef0123456789abcdef01234567", "profile": "vita", "version": "1", "hosts": [{"name": "a", "stage": 1, "runner": "r"}]}' \
	"schema 2 against a schema-1 shell"

# 3. Malformed JSON fails.
assert_fails 'not json' "malformed JSON"

# 4. A missing required field fails.
assert_fails '{"schema": 1, "buildscripts_revision": "0123456789abcdef0123456789abcdef01234567", "profile": "vita", "version": "1", "hosts": [{"name": "a", "stage": 1, "runner": "r"}]}' \
	"missing build_id"

# 5. A non-40-hex revision fails.
assert_fails '{"schema": 1, "build_id": "x", "buildscripts_revision": "short", "profile": "vita", "version": "1", "hosts": [{"name": "a", "stage": 1, "runner": "r"}]}' \
	"short revision"

# 6. Empty hosts[] fails.
assert_fails '{"schema": 1, "build_id": "x", "buildscripts_revision": "0123456789abcdef0123456789abcdef01234567", "profile": "vita", "version": "1", "hosts": []}' \
	"empty hosts"

# 7. A host declaring a stage outside {1,2,3} under schema 1 fails.
assert_fails '{"schema": 1, "build_id": "x", "buildscripts_revision": "0123456789abcdef0123456789abcdef01234567", "profile": "vita", "version": "1", "hosts": [{"name": "a", "stage": 4, "runner": "r"}]}' \
	"stage 4 under schema 1"

# 8. A duplicate (name, stage) pair fails; the same name at two different
# stages does not (see the good_lock fixture above).
assert_fails '{"schema": 1, "build_id": "x", "buildscripts_revision": "0123456789abcdef0123456789abcdef01234567", "profile": "vita", "version": "1", "hosts": [{"name": "a", "stage": 1, "runner": "r"}, {"name": "a", "stage": 1, "runner": "r"}]}' \
	"duplicate (name, stage) pair"

# 9. A stage with no hosts groups to an empty JSON array, the shell's signal
# to skip that stage job without failing.
output=$(run_parse '{"schema": 1, "build_id": "x", "buildscripts_revision": "0123456789abcdef0123456789abcdef01234567", "profile": "vita", "version": "1", "hosts": [{"name": "a", "stage": 1, "runner": "r"}]}')
[[ $(output_value "$output" stage2_hosts) == '[]' ]]
[[ $(output_value "$output" stage3_hosts) == '[]' ]]

printf 'parse-lock.py contract tests passed\n'
