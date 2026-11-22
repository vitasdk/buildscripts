#!/usr/bin/env python3
"""Announce one SDK-core build for every profile published by this tree."""

import argparse
import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from describe import DescribeError, parse_profiles  # noqa: E402

REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_PROFILES_PATH = REPOSITORY_ROOT / "cmake" / "Profiles.cmake"


class AnnounceError(Exception):
    pass


def load_profiles(path):
    try:
        text = pathlib.Path(path).read_text(encoding="utf-8")
    except OSError as exc:
        raise AnnounceError(f"{path} cannot be read: {exc}") from exc
    try:
        return parse_profiles(text)
    except DescribeError as exc:
        raise AnnounceError(str(exc)) from exc


def announce(repository, revision, profiles):
    failures = []
    for profile in profiles:
        try:
            result = subprocess.run(
                [
                    "gh",
                    "api",
                    f"repos/{repository}/dispatches",
                    "-f",
                    "event_type=run_build",
                    "-f",
                    f"client_payload[buildscripts_ref]={revision}",
                    "-f",
                    f"client_payload[profile]={profile}",
                ],
                check=False,
            )
        except OSError as exc:
            raise AnnounceError(f"cannot run gh: {exc}") from exc
        if result.returncode != 0:
            failures.append((profile, result.returncode))

    if failures:
        detail = ", ".join(f"{profile} (exit {status})" for profile, status in failures)
        raise AnnounceError(f"dispatch failed for: {detail}")


def main(argv):
    parser = argparse.ArgumentParser(prog="announce-builds")
    parser.add_argument("--repository", required=True)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--profiles-file", default=DEFAULT_PROFILES_PATH)
    args = parser.parse_args(argv)

    try:
        profiles = load_profiles(args.profiles_file)
        announce(args.repository, args.revision, profiles)
    except AnnounceError as exc:
        print(f"announce-builds: {exc}", file=sys.stderr)
        return 1

    print(f"announce-builds: requested {len(profiles)} profile build(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
