#!/usr/bin/env bash
# There is one matrix, and it is the one that publishes.
#
# This repository used to describe its hosts twice: cmake/hosts.json, which
# the lock is made of and which autobuilds builds through build-host.sh, and
# a hand-written matrix in build.yml that ran cmake straight from the job.
# The two drifted, and the drift is silent in the worst direction -- a pull
# request goes green having built the hosts by the route nobody publishes.
# db4d1a593 merged that way with the Intel Mac host broken.

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
failures=0

report()
{
	printf 'FAIL: %s\n' "$1" >&2
	failures=$((failures + 1))
}

while IFS= read -r problem; do
	report "$problem"
done < <(python3 - "$repository_root" <<'PYEOF'
import json
import re
import sys

import yaml

root = sys.argv[1]
workflow = yaml.safe_load(open(f"{root}/.github/workflows/build.yml"))
text = open(f"{root}/.github/workflows/build.yml").read()
jobs = workflow["jobs"]

caller = next(
    (name for name, job in jobs.items()
     if str(job.get("uses", "")).endswith("build-sdk.yml")),
    None,
)
if caller is None:
    print("build.yml builds nothing through build-sdk.yml, the workflow that publishes")
    sys.exit()

# Local, not vitasdk/buildscripts@master: called by path, a pull request that
# changes the reusable workflow is tested by its own build.
if not str(jobs[caller]["uses"]).startswith("./"):
    print(f"job {caller!r} calls build-sdk.yml from another revision than the one under review")

lock = str(jobs[caller].get("with", {}).get("lock", ""))
if "outputs.lock" not in lock:
    print(f"job {caller!r} is handed something other than the lock describe produced")

for name, job in jobs.items():
    if "strategy" in job:
        print(f"job {name!r} declares a matrix of its own; the hosts come from the lock")

# Nothing host-shaped may be named here: a host name, a cross toolchain file,
# or a runner that only exists to build one. That is the second matrix
# growing back, one row at a time.
hosts = json.load(open(f"{root}/cmake/hosts.json"))["hosts"]
for name in sorted({host["name"] for host in hosts}):
    if re.search(rf"\b{re.escape(name)}\b", text):
        print(f"build.yml names the host {name!r}; cmake/hosts.json is where hosts are declared")
for runner in sorted({host["runner"] for host in hosts} - {"ubuntu-24.04"}):
    if runner in text:
        print(f"build.yml names the runner {runner!r}; cmake/hosts.json is where runners are declared")
if "cmake/toolchains/" in text:
    print("build.yml names a cross toolchain file; build-host.sh is where a host is built")

# And it must not run that one path twice. A push to master is announced to
# autobuilds, which describes the same revision and builds the same lock, so
# building it here too is the same legs over again.
def evaluate(expression, context):
    tokens = re.findall(r"'[^']*'|\|\||&&|==|!=|[A-Za-z0-9_.-]+", expression)
    position = 0

    def take():
        nonlocal position
        position += 1
        return tokens[position - 1]

    def primary():
        token = take()
        if token.startswith("'"):
            return token[1:-1]
        value = context
        for part in token.split("."):
            value = value.get(part, "") if isinstance(value, dict) else ""
        return value

    def comparison():
        left = primary()
        if position < len(tokens) and tokens[position] in ("==", "!="):
            operator = take()
            right = primary()
            return left == right if operator == "==" else left != right
        return left

    def conjunction():
        value = comparison()
        while position < len(tokens) and tokens[position] == "&&":
            take()
            right = comparison()
            value = right if value else value
        return value

    value = conjunction()
    while position < len(tokens) and tokens[position] == "||":
        take()
        right = conjunction()
        value = value if value else right
    return value


def runs_on(event_name, ref):
    condition = str(jobs[caller].get("if", "")).strip()
    if not condition:
        return True
    return bool(evaluate(condition, {"github": {"event_name": event_name, "ref": ref}}))


if runs_on("push", "refs/heads/master"):
    print("a push to master builds here as well as in autobuilds; that is the same lock twice")
if not runs_on("pull_request", "refs/pull/1/merge"):
    print("a pull request no longer builds, which is the only place this build is the signal")
PYEOF
)

if [[ $failures -gt 0 ]]; then
	printf '%s check(s) failed\n' "$failures" >&2
	exit 1
fi
printf 'single matrix: all checks passed\n'
