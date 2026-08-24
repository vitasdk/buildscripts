#!/usr/bin/env python3
"""Gate step for the reusable build workflow: validates the lock's schema
and groups hosts[] by stage."""
import json
import os
import sys

SUPPORTED_SCHEMA = 1
SUPPORTED_STAGES = (1, 2, 3)


def fail(message):
    print(f"::error::{message}", file=sys.stderr)
    sys.exit(1)


def write_output(name, value):
    path = os.environ["GITHUB_OUTPUT"]
    delimiter = f"__parse_lock_{name}__"
    with open(path, "a", encoding="utf-8") as handle:
        handle.write(f"{name}<<{delimiter}\n{value}\n{delimiter}\n")


def main():
    raw = os.environ.get("LOCK_JSON", "")
    try:
        lock = json.loads(raw)
    except json.JSONDecodeError as exc:
        fail(f"lock input is not valid JSON: {exc}")
        return

    if not isinstance(lock, dict):
        fail("lock input must be a JSON object")

    schema = lock.get("schema")
    if schema != SUPPORTED_SCHEMA:
        fail(
            "unsupported lock schema: this shell supports schema "
            f"{SUPPORTED_SCHEMA}, the lock declares schema {schema!r}"
        )

    for field in ("build_id", "buildscripts_revision", "profile", "version"):
        if not isinstance(lock.get(field), str) or not lock[field]:
            fail(f"lock is missing required string field: {field}")

    revision = lock["buildscripts_revision"]
    if len(revision) != 40 or any(c not in "0123456789abcdefABCDEF" for c in revision):
        fail(f"buildscripts_revision is not a 40-character git SHA: {revision!r}")

    hosts = lock.get("hosts")
    if not isinstance(hosts, list) or not hosts:
        fail("lock carries no hosts[]")
        return

    by_stage = {stage: [] for stage in SUPPORTED_STAGES}
    # A name may legitimately recur across stages; only the pair is unique.
    seen_pairs = set()
    for host in hosts:
        if not isinstance(host, dict):
            fail(f"malformed host entry: {host!r}")
        name = host.get("name")
        stage = host.get("stage")
        runner = host.get("runner")
        if not isinstance(name, str) or not name:
            fail(f"host entry has no name: {host!r}")
        if (name, stage) in seen_pairs:
            fail(f"duplicate (name, stage) pair in lock: ({name}, {stage})")
        seen_pairs.add((name, stage))
        if stage not in SUPPORTED_STAGES:
            fail(
                f"host {name!r} declares stage {stage!r}, which schema "
                f"{SUPPORTED_SCHEMA} does not define (supported: {SUPPORTED_STAGES})"
            )
        if not isinstance(runner, str) or not runner:
            fail(f"host {name!r} has no runner")
        by_stage[stage].append({
            "name": name,
            "stage": stage,
            "runner": runner,
            "container": host.get("container") or "",
        })

    write_output("schema", str(schema))
    write_output("build_id", lock["build_id"])
    write_output("buildscripts_revision", revision)
    write_output("profile", lock["profile"])
    write_output("version", lock["version"])
    for stage in SUPPORTED_STAGES:
        write_output(f"stage{stage}_hosts", json.dumps(by_stage[stage]))


if __name__ == "__main__":
    main()
