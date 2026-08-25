#!/usr/bin/env python3
"""Turns a buildscripts checkout at one revision/profile into a lock."""

import argparse
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vercmp import vercmp  # noqa: E402

SCHEMA = 1
COMPONENTS_PATH = "cmake/Components.cmake"
PROFILES_PATH = "cmake/Profiles.cmake"
HOSTS_PATH = "cmake/hosts.json"
STABLE_VERSION_PATH = "VERSION"

# A floor, not the whole set: parse_components() also picks up any extra pin.
REQUIRED_SOURCES = [
    "gcc", "zlib", "libelf", "libyaml", "gmp", "mpfr", "mpc", "isl", "expat",
    "binutils", "gdb", "libzip", "newlib", "samples", "headers", "toolchain",
    "pthread", "vdpm", "vita-makepkg",
]

SET_PATTERN = re.compile(r'set\(\s*([A-Za-z0-9_]+)\s+"?([^")\s]+)"?')
VARIABLE_REFERENCE = re.compile(r"\$\{([A-Za-z0-9_]+)\}")


class DescribeError(Exception):
    pass


def _git(*args):
    try:
        result = subprocess.run(["git", *args], capture_output=True, text=True)
    except FileNotFoundError as exc:
        raise DescribeError(f"git is not available: {exc}") from exc
    if result.returncode != 0:
        raise DescribeError(result.stderr.strip() or f"git {' '.join(args)} failed")
    return result.stdout


def resolve_revision(revision):
    return _git("rev-parse", "--verify", f"{revision}^{{commit}}").strip()


def read_file_at(revision, path):
    result = subprocess.run(
        ["git", "show", f"{revision}:{path}"], capture_output=True, text=True
    )
    if result.returncode != 0:
        return None
    return result.stdout


def committer_epoch(revision):
    return int(_git("log", "-1", "--format=%ct", revision).strip())


def first_parent(revision):
    result = subprocess.run(
        ["git", "rev-parse", f"{revision}^"], capture_output=True, text=True
    )
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def first_parent_count(revision):
    return int(_git("rev-list", "--count", "--first-parent", revision).strip())


def parse_profiles(text):
    if text is None:
        raise DescribeError(f"{PROFILES_PATH} is missing at this revision")
    match = re.search(r"set\(\s*VITASDK_PROFILES\s+([^)]+)\)", text)
    if not match:
        raise DescribeError(f"{PROFILES_PATH} does not declare VITASDK_PROFILES")
    profiles = match.group(1).split()
    if not profiles:
        raise DescribeError(f"{PROFILES_PATH} declares no profiles")
    return profiles


def parse_hosts(text):
    if text is None:
        raise DescribeError(f"{HOSTS_PATH} is missing at this revision")
    try:
        data = json.loads(text)
    except json.JSONDecodeError as exc:
        raise DescribeError(f"{HOSTS_PATH} is not valid JSON: {exc}") from exc
    hosts = data.get("hosts") if isinstance(data, dict) else None
    if not isinstance(hosts, list) or not hosts:
        raise DescribeError(f"{HOSTS_PATH} declares no hosts")
    for host in hosts:
        for key in ("name", "stage", "runner", "container"):
            if not isinstance(host, dict) or key not in host:
                raise DescribeError(f"{HOSTS_PATH} entry missing '{key}': {host}")
        # Older revisions predate the packaged marker; treat it as unpublished.
        host.setdefault("packaged", False)
    seen = set()
    for host in hosts:
        key = (host["name"], host["stage"])
        if key in seen:
            raise DescribeError(f"{HOSTS_PATH} lists {key} more than once")
        seen.add(key)
    return hosts


def prune_hosts(hosts):
    # (name, stage) is a host entry's uniqueness key: the same name can
    # recur across stages (e.g. the stage-1/stage-2 x86_64-linux-gnu rows).
    by_key = {(host["name"], host["stage"]): host for host in hosts}
    kept = {key for key, host in by_key.items() if host["stage"] == 1 or host["packaged"]}
    for host in hosts:
        if host["stage"] != 3 or not host["packaged"]:
            continue
        build_host = host.get("build_host")
        if not build_host:
            raise DescribeError(
                f"{HOSTS_PATH}: packaged stage-3 host {host['name']} "
                "declares no build_host"
            )
        key = (build_host, 2)
        if key not in by_key:
            raise DescribeError(
                f"{HOSTS_PATH}: {host['name']} stage 3 references "
                f"unknown build_host '{build_host}'"
            )
        kept.add(key)
    return [host for host in hosts if (host["name"], host["stage"]) in kept]


def parse_components(text):
    if text is None:
        raise DescribeError(f"{COMPONENTS_PATH} is missing at this revision")
    raw = dict(SET_PATTERN.findall(text))

    def resolve(value, seen=()):
        def substitute(match):
            name = match.group(1)
            if name in seen:
                raise DescribeError(f"{COMPONENTS_PATH}: circular reference on {name}")
            if name not in raw:
                raise DescribeError(
                    f"{COMPONENTS_PATH} references undefined variable {name}"
                )
            return resolve(raw[name], seen + (name,))

        return VARIABLE_REFERENCE.sub(substitute, value)

    names = sorted(
        {name[: -len("_TAG")] for name in raw if name.endswith("_TAG")}
        | {name[: -len("_HASH")] for name in raw if name.endswith("_HASH")}
    )
    sources = {}
    for name in names:
        raw_value = raw.get(f"{name}_TAG", raw.get(f"{name}_HASH"))
        value = resolve(raw_value)
        if not value:
            raise DescribeError(f"{COMPONENTS_PATH}: {name} has an empty pin")
        sources[name.lower().replace("_", "-")] = value

    missing = [name for name in REQUIRED_SOURCES if name not in sources]
    if missing:
        raise DescribeError(
            f"{COMPONENTS_PATH} is missing pins for: {', '.join(missing)}"
        )
    return sources


def compute_build_id(schema, revision, profile):
    payload = f"{schema}\n{revision}\n{profile}\n".encode("utf-8")
    return "sha256:" + hashlib.sha256(payload).hexdigest()


def nightly_version(revision):
    epoch = committer_epoch(revision)
    date = datetime.datetime.fromtimestamp(
        epoch, datetime.timezone.utc
    ).strftime("%Y%m%d")
    count = first_parent_count(revision)
    return f"0.{date}.{count}"


def stable_version_declaration(revision):
    text = read_file_at(revision, STABLE_VERSION_PATH)
    if text is None:
        return None
    value = text.strip()
    return value or None


def check_first_parent_date(revision):
    parent = first_parent(revision)
    if parent is None:
        return
    if committer_epoch(revision) < committer_epoch(parent):
        raise DescribeError(
            f"committer date of {revision} precedes its first parent {parent}"
        )


def build_lock(revision, profile, previous_version):
    resolved = resolve_revision(revision)

    profiles = parse_profiles(read_file_at(resolved, PROFILES_PATH))
    if profile not in profiles:
        raise DescribeError(
            f"unknown profile '{profile}'; known profiles: {', '.join(profiles)}"
        )

    sources = parse_components(read_file_at(resolved, COMPONENTS_PATH))
    hosts = prune_hosts(parse_hosts(read_file_at(resolved, HOSTS_PATH)))

    declared = stable_version_declaration(resolved)
    if declared is not None:
        version = declared
    else:
        check_first_parent_date(resolved)
        version = nightly_version(resolved)

    # Both paths, and the declared one most of all: a nightly version is
    # derived and cannot go backwards by accident, but a stable one is typed
    # by a person. The caller passes the last version of the channel it is
    # about to publish to -- comparing across channels is meaningless, since
    # every nightly sorts below every stable.
    if previous_version is not None and vercmp(version, previous_version) <= 0:
        raise DescribeError(
            f"candidate version {version} does not exceed "
            f"previous version {previous_version}"
        )

    return {
        "schema": SCHEMA,
        "build_id": compute_build_id(SCHEMA, resolved, profile),
        "buildscripts_revision": resolved,
        "profile": profile,
        "version": version,
        "hosts": hosts,
        "sources": sources,
    }


def main(argv):
    parser = argparse.ArgumentParser(prog="buildscripts-ci describe")
    parser.add_argument("--profile", required=True)
    parser.add_argument("--revision", default="HEAD")
    parser.add_argument("--previous-version", default=None)
    parser.add_argument("--output")
    args = parser.parse_args(argv)

    try:
        lock = build_lock(args.revision, args.profile, args.previous_version)
    except DescribeError as exc:
        print(f"describe: {exc}", file=sys.stderr)
        return 1

    text = json.dumps(lock, indent=2) + "\n"
    if args.output:
        with open(args.output, "w", encoding="utf-8") as handle:
            handle.write(text)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
