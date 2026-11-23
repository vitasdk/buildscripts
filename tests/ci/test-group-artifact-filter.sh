#!/usr/bin/env bash
# A partial workflow rerun retains artifacts from earlier attempts. Grouping
# must consume only stage artifacts, never its own previous output.

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)

python3 - "$repository_root" <<'PY'
import fnmatch
import re
import sys

root = sys.argv[1]
text = open(f"{root}/.github/workflows/build-sdk.yml", encoding="utf-8").read()
group_match = re.search(
    r"(?ms)^  group:\n(?P<body>.*?)(?=^  [A-Za-z0-9_-]+:\n|\Z)", text
)
if group_match is None:
    raise SystemExit("build-sdk.yml has no group job")
body = group_match.group("body")
downloads = list(
    re.finditer(r"(?m)^      - uses: actions/download-artifact@[^\n]+$", body)
)
if len(downloads) != 1:
    raise SystemExit(f"group job has {len(downloads)} artifact download steps, expected one")

step = body[downloads[0].start():]
next_step = re.search(r"(?m)^      - ", step[1:])
if next_step is not None:
    step = step[: next_step.start() + 1]
pattern_match = re.search(r"(?m)^          pattern:\s*['\"]?([^'\"\n]+)['\"]?\s*$", step)
if pattern_match is None:
    raise SystemExit("group artifact download has no filter and can ingest an earlier grouped-sdk-snapshot")
pattern = pattern_match.group(1).strip()

for artifact in ("stage1-host", "stage2-host", "stage3-host"):
    if not fnmatch.fnmatchcase(artifact, pattern):
        raise SystemExit(f"group artifact pattern {pattern!r} excludes {artifact!r}")
if fnmatch.fnmatchcase("grouped-sdk-snapshot", pattern):
    raise SystemExit(f"group artifact pattern {pattern!r} re-ingests grouped-sdk-snapshot")
PY

printf 'group artifact filter contract passed\n'
