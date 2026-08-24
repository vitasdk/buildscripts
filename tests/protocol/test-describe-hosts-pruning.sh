#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/vitasdk-describe-hosts.XXXXXXXX")
cleanup() { rm -rf -- "$temporary_root"; }
trap cleanup EXIT

clone="$temporary_root/clone"
git clone --quiet "$repository_root" "$clone"
git -C "$clone" config user.email describe-tests@ci.invalid
git -C "$clone" config user.name "describe tests"

describe() {
	python3 "$repository_root/scripts/describe.py" "$@"
}

host_keys() {
	python3 -c '
import json, sys
data = json.load(sys.stdin)
for host in data["hosts"]:
    print(host["name"] + ":" + str(host["stage"]))
'
}

cd "$clone"

cat > cmake/hosts.json <<'EOF'
{
  "hosts": [
    { "name": "stage1-host", "stage": 1, "runner": "r1", "container": null, "packaged": false },
    { "name": "linux-build", "stage": 2, "runner": "r2", "container": null, "packaged": false },
    { "name": "unreferenced-host", "stage": 2, "runner": "r3", "container": null, "packaged": false },
    { "name": "packaged-host", "stage": 2, "runner": "r4", "container": null, "packaged": true },
    { "name": "cross-host", "stage": 3, "runner": "r5", "container": null, "packaged": true, "build_host": "linux-build" }
  ]
}
EOF
git commit -aq -m 'test: synthetic hosts.json for pruning'
synthetic_rev=$(git rev-parse HEAD)

output=$(describe --profile vita --revision "$synthetic_rev")
kept=$(host_keys <<< "$output")

# The stage-1 row is a structural dependency, kept regardless of packaged.
grep -qx 'stage1-host:1' <<< "$kept" || {
	printf 'the stage-1 row was pruned\n' >&2
	exit 1
}

# A packaged stage-3 host's build_host is pulled in even though it is
# itself unpackaged.
grep -qx 'linux-build:2' <<< "$kept" || {
	printf 'a packaged host build_host was pruned instead of being pulled in\n' >&2
	exit 1
}

# Packaged rows are kept.
grep -qx 'packaged-host:2' <<< "$kept" || {
	printf 'a packaged row was pruned\n' >&2
	exit 1
}
grep -qx 'cross-host:3' <<< "$kept" || {
	printf 'a packaged stage-3 row was pruned\n' >&2
	exit 1
}

# An unpackaged row with no dependent must not appear.
if grep -qx 'unreferenced-host:2' <<< "$kept"; then
	printf 'an unpackaged row with no dependent was not pruned\n' >&2
	exit 1
fi

# packaged and build_host travel through the lock verbatim.
python3 -c '
import json, sys
hosts = {(h["name"], h["stage"]): h for h in json.loads(sys.argv[1])["hosts"]}
cross = hosts[("cross-host", 3)]
assert cross["packaged"] is True
assert cross["build_host"] == "linux-build"
linux_build = hosts[("linux-build", 2)]
assert linux_build["packaged"] is False
' "$output"

# A packaged stage-3 host referencing a build_host that does not exist at
# stage 2 fails loudly instead of silently dropping the dependency.
python3 -c '
import json
data = json.load(open("cmake/hosts.json"))
data["hosts"].append({
    "name": "dangling-cross", "stage": 3, "runner": "r6", "container": None,
    "packaged": True, "build_host": "does-not-exist",
})
json.dump(data, open("cmake/hosts.json", "w"))
'
git commit -aq -m 'test: dangling build_host reference'
dangling_rev=$(git rev-parse HEAD)

if output=$(describe --profile vita --revision "$dangling_rev" 2>&1); then
	printf 'describe accepted a build_host that does not resolve to a stage-2 host\n' >&2
	exit 1
fi
grep -qi 'does-not-exist' <<< "$output" || {
	printf 'describe did not name the unresolved build_host: %s\n' "$output" >&2
	exit 1
}

printf 'describe host-pruning contract tests passed\n'
