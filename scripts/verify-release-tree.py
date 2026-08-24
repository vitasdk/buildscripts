#!/usr/bin/env python3
"""Black-box validator for a grouped VitaSDK release tree (buildscripts-ci verify)."""

import argparse
import hashlib
import json
import os
import sys

SUPPORTED_SCHEMA = 1
MANIFEST_NAME = "release.json"
CHECKSUM_NAME = "SHA256SUMS"


class VerificationError(Exception):
    pass


def fail(message):
    raise VerificationError(message)


def require_string(value, field):
    if not isinstance(value, str) or not value:
        fail(f"{field} must be a non-empty string")
    return value


def require_revision(value, field):
    value = require_string(value, field)
    if len(value) != 40 or any(c not in "0123456789abcdef" for c in value.lower()):
        fail(f"{field} is not a 40-character git revision: {value!r}")
    return value


def safe_relative_path(value, context):
    value = require_string(value, context)
    parts = value.split("/")
    if any(part in ("", ".", "..") for part in parts):
        fail(f"{context} is not a safe relative path: {value!r}")
    return value


def load_manifest(tree):
    manifest_path = os.path.join(tree, MANIFEST_NAME)
    if not os.path.isfile(manifest_path):
        fail(f"missing release manifest: {MANIFEST_NAME}")
    with open(manifest_path, encoding="utf-8") as handle:
        try:
            manifest = json.load(handle)
        except json.JSONDecodeError as exc:
            fail(f"{MANIFEST_NAME} is not valid JSON: {exc}")
    if not isinstance(manifest, dict):
        fail(f"{MANIFEST_NAME} does not contain a JSON object")
    return manifest


def validate_manifest(manifest):
    schema = manifest.get("schema")
    if schema != SUPPORTED_SCHEMA:
        fail(
            f"unsupported release manifest schema: tree declares {schema!r}, "
            f"this verify supports {SUPPORTED_SCHEMA}"
        )

    build_id = require_string(manifest.get("build_id"), "build_id")
    require_revision(manifest.get("buildscripts_revision"), "buildscripts_revision")
    require_string(manifest.get("profile"), "profile")

    hosts = manifest.get("hosts")
    if not isinstance(hosts, list) or not hosts:
        fail("hosts must be a non-empty list")

    declared_files = {MANIFEST_NAME, CHECKSUM_NAME}
    seen_hosts = set()
    for entry in hosts:
        if not isinstance(entry, dict):
            fail("each hosts[] entry must be an object")
        name = require_string(entry.get("name"), "hosts[].name")
        if name in seen_hosts:
            fail(f"duplicate host in manifest: {name}")
        seen_hosts.add(name)

        host_build_id = require_string(entry.get("build_id"), f"hosts[{name}].build_id")
        if host_build_id != build_id:
            fail(
                f"host {name} echoes build_id {host_build_id!r}, "
                f"the manifest declares {build_id!r}"
            )

        artifacts = entry.get("artifacts")
        if not isinstance(artifacts, list) or not artifacts:
            fail(f"hosts[{name}].artifacts must be a non-empty list")
        for artifact in artifacts:
            declared_files.add(safe_relative_path(artifact, f"hosts[{name}].artifacts[]"))

    return build_id, len(hosts), declared_files


def list_tree_files(tree):
    # the distribution contract is a flat tree: no subdirectories anywhere
    files = set()
    for entry in os.listdir(tree):
        path = os.path.join(tree, entry)
        if os.path.islink(path) or not os.path.isfile(path):
            fail(f"grouped release tree contains a non-regular entry: {entry}")
        files.add(entry)
    return files


def parse_checksum_file(path):
    recorded = {}
    with open(path, encoding="utf-8") as handle:
        for lineno, raw_line in enumerate(handle, 1):
            line = raw_line.rstrip("\r\n")
            if not line:
                continue
            parts = line.split(None, 1)
            if len(parts) != 2:
                fail(f"{CHECKSUM_NAME}:{lineno}: malformed line: {line!r}")
            digest, filename = parts
            if filename.startswith("*"):
                filename = filename[1:]
            if filename in recorded:
                fail(f"{CHECKSUM_NAME} lists {filename} more than once")
            recorded[filename] = digest.lower()
    return recorded


def sha256_of(path):
    hasher = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def verify_checksums(tree, expected_hashed):
    checksum_path = os.path.join(tree, CHECKSUM_NAME)
    recorded = parse_checksum_file(checksum_path)

    recorded_files = set(recorded)
    if recorded_files != expected_hashed:
        details = []
        missing = sorted(expected_hashed - recorded_files)
        extra = sorted(recorded_files - expected_hashed)
        if missing:
            details.append(f"missing from {CHECKSUM_NAME}: {', '.join(missing)}")
        if extra:
            details.append(f"unexpected in {CHECKSUM_NAME}: {', '.join(extra)}")
        fail("; ".join(details))

    for filename in sorted(recorded):
        actual = sha256_of(os.path.join(tree, filename))
        expected = recorded[filename]
        if actual != expected:
            fail(f"checksum mismatch for {filename}: expected {expected}, got {actual}")


def verify_tree(tree):
    if not os.path.isdir(tree):
        fail(f"release tree not found: {tree}")

    manifest = load_manifest(tree)
    build_id, host_count, declared_files = validate_manifest(manifest)

    actual_files = list_tree_files(tree)
    missing = sorted(declared_files - actual_files)
    extra = sorted(actual_files - declared_files)
    if missing or extra:
        details = []
        if missing:
            details.append(f"missing declared artifacts: {', '.join(missing)}")
        if extra:
            details.append(f"undeclared files present: {', '.join(extra)}")
        fail("; ".join(details))

    expected_hashed = declared_files - {CHECKSUM_NAME}
    verify_checksums(tree, expected_hashed)

    artifact_count = len(declared_files) - 2  # exclude the manifest and SHA256SUMS
    print(
        f"verified release tree: build_id={build_id} "
        f"hosts={host_count} artifacts={artifact_count}"
    )


def main(argv):
    parser = argparse.ArgumentParser(prog="buildscripts-ci verify")
    parser.add_argument("--tree", required=True, help="grouped release tree to validate")
    args = parser.parse_args(argv)

    try:
        verify_tree(os.path.realpath(args.tree))
    except VerificationError as exc:
        print(f"verify: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
