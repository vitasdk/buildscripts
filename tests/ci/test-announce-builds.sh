#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/vitasdk-announce-builds.XXXXXXXX")
cleanup() { rm -rf -- "$temporary_root"; }
trap cleanup EXIT

workflow="$repository_root/.github/workflows/dispatch-build.yml"
grep -Fq './scripts/announce-builds.py' "$workflow" || {
	printf 'the revision announcement workflow does not use the profile fan-out helper\n' >&2
	exit 1
}
grep -Fq 'actions/checkout@' "$workflow" || {
	message='the revision announcement workflow cannot read the declared profiles without a checkout'
	printf '%s\n' "$message" >&2
	exit 1
}
grep -Fq -- '--repository vitasdk/autobuilds' "$workflow" || {
	printf 'the revision announcement workflow targets the wrong repository\n' >&2
	exit 1
}
grep -Fq -- '--revision "$GITHUB_SHA"' "$workflow" || {
	printf 'the revision announcement workflow does not announce its pushed revision\n' >&2
	exit 1
}

profiles="$temporary_root/Profiles.cmake"
cat > "$profiles" <<'CMAKEEOF'
set(VITASDK_PROFILES vita vita_softfp future_world)
CMAKEEOF

mkdir -p "$temporary_root/bin"
cat > "$temporary_root/bin/gh" <<'PYEOF'
#!/usr/bin/env python3
import json
import os
import sys

with open(os.environ["RECORDED_CALLS"], "a", encoding="utf-8") as handle:
    json.dump(sys.argv[1:], handle)
    handle.write("\n")

profile = next(
    (argument.split("=", 1)[1] for argument in sys.argv[1:]
     if argument.startswith("client_payload[profile]=")),
    None,
)
if profile == os.environ.get("FAIL_PROFILE"):
    sys.exit(17)
PYEOF
chmod +x "$temporary_root/bin/gh"

recorded="$temporary_root/calls.jsonl"
announce() {
	PATH="$temporary_root/bin:$PATH" \
	RECORDED_CALLS="$recorded" \
	python3 "$repository_root/scripts/announce-builds.py" \
		--profiles-file "$profiles" \
		--repository vitasdk/autobuilds \
		--revision 0123456789abcdef
}

announce
python3 - "$recorded" <<'PYEOF'
import json
import sys

calls = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
expected_profiles = ["vita", "vita_softfp", "future_world"]
assert len(calls) == len(expected_profiles), calls
for call, profile in zip(calls, expected_profiles):
    assert call == [
        "api",
        "repos/vitasdk/autobuilds/dispatches",
        "-f",
        "event_type=run_build",
        "-f",
        "client_payload[buildscripts_ref]=0123456789abcdef",
        "-f",
        f"client_payload[profile]={profile}",
    ], call
PYEOF

: > "$recorded"
if failure=$(FAIL_PROFILE=vita announce 2>&1); then
	printf 'a failed profile dispatch did not fail the announcement\n' >&2
	exit 1
fi
grep -q 'vita (exit 17)' <<< "$failure" || {
	printf 'the failed dispatch was not identified: %s\n' "$failure" >&2
	exit 1
}
python3 - "$recorded" <<'PYEOF'
import json
import sys

calls = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
profiles = [
    next(argument.split("=", 1)[1] for argument in call
         if argument.startswith("client_payload[profile]="))
    for call in calls
]
assert profiles == ["vita", "vita_softfp", "future_world"], profiles
PYEOF

printf 'announce-builds: all checks passed\n'
