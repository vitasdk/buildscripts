#!/usr/bin/env python3
"""Moves the tracked source pins to what their upstream branches hold now."""

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile

COMPONENTS_PATH = "cmake/Components.cmake"
TRACKING_PATH = "cmake/pin-tracking.json"
SCHEMA = 1

SET_PATTERN = re.compile(r'set\(\s*([A-Za-z0-9_]+)\s+"?([^")\s]+)"?')
VARIABLE_REFERENCE = re.compile(r"\$\{([A-Za-z0-9_]+)\}")


class BumpError(Exception):
    pass


def component_name(variable):
    return variable.lower().replace("_", "-")


def parse_components(text):
    """Every component pinned by repository plus revision, by lock name."""

    raw = dict(SET_PATTERN.findall(text))

    def resolve(value, seen=()):
        def substitute(match):
            name = match.group(1)
            if name in seen:
                raise BumpError(f"{COMPONENTS_PATH}: circular reference on {name}")
            if name not in raw:
                raise BumpError(
                    f"{COMPONENTS_PATH} references undefined variable {name}"
                )
            return resolve(raw[name], seen + (name,))

        return VARIABLE_REFERENCE.sub(substitute, value)

    components = {}
    for variable, value in raw.items():
        if not variable.endswith("_REPOSITORY"):
            continue
        prefix = variable[: -len("_REPOSITORY")]
        if f"{prefix}_TAG" not in raw:
            continue
        components[component_name(prefix)] = {
            "variable": prefix,
            "repository": resolve(value),
            "pin": resolve(raw[f"{prefix}_TAG"]),
        }
    if not components:
        raise BumpError(f"{COMPONENTS_PATH} declares no git-pinned component")
    return components


def load_tracking(path, components):
    try:
        with open(path, encoding="utf-8") as handle:
            config = json.load(handle)
    except OSError as exc:
        raise BumpError(f"{path} cannot be read: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise BumpError(f"{path} is not valid JSON: {exc}") from exc

    if config.get("schema") != SCHEMA:
        raise BumpError(f"{path} declares schema {config.get('schema')}, expected {SCHEMA}")
    tracked = config.get("tracked")
    untracked = config.get("untracked")
    if not isinstance(tracked, dict) or not isinstance(untracked, dict):
        raise BumpError(f"{path} must declare 'tracked' and 'untracked' as objects")

    both = sorted(set(tracked) & set(untracked))
    if both:
        raise BumpError(f"{path} lists as both tracked and untracked: {', '.join(both)}")
    unknown = sorted((set(tracked) | set(untracked)) - set(components))
    if unknown:
        raise BumpError(
            f"{path} names components that are not pinned in {COMPONENTS_PATH}: "
            f"{', '.join(unknown)}"
        )
    # The point of the file: a pin added to the build cannot stay undeclared,
    # in either direction, without this failing before anything is resolved.
    undeclared = sorted(set(components) - set(tracked) - set(untracked))
    if undeclared:
        raise BumpError(
            f"{path} declares neither tracking nor a reason for: {', '.join(undeclared)}"
        )

    for name, entry in tracked.items():
        branch = entry.get("branch") if isinstance(entry, dict) else None
        if not branch:
            raise BumpError(f"{path}: tracked component {name} declares no branch")
    for name, reason in untracked.items():
        if not isinstance(reason, str) or not reason.strip():
            raise BumpError(f"{path}: untracked component {name} gives no reason")
    return {name: entry["branch"] for name, entry in tracked.items()}


def resolve_branch(repository, branch):
    result = subprocess.run(
        ["git", "ls-remote", "--exit-code", repository, f"refs/heads/{branch}"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise BumpError(
            f"{repository} has no branch {branch}: "
            f"{result.stderr.strip() or 'git ls-remote failed'}"
        )
    return result.stdout.split()[0]


def contains(repository, pin, branch):
    """Whether what the branch holds now was built on top of the pin.

    A pin that moves to a revision not descended from it is a rollback:
    a force-push upstream, a branch that is not where the work happens,
    a pin taken from somewhere else. The bot refuses and a person looks.
    """

    probe = tempfile.mkdtemp(prefix="bump-pins-")
    try:
        subprocess.run(["git", "init", "--quiet", probe], check=True)
        # tree:0 asks for commits and nothing else: the whole history of
        # the largest leaf arrives in a few megabytes and a few seconds.
        fetch = subprocess.run(
            [
                "git", "-C", probe, "fetch", "--quiet", "--filter=tree:0",
                "--no-tags", repository,
                f"+refs/heads/{branch}:refs/heads/tracked", pin,
            ],
            capture_output=True,
            text=True,
        )
        if fetch.returncode != 0:
            raise BumpError(
                f"{repository} cannot serve {pin} and {branch} together: "
                f"{fetch.stderr.strip() or 'git fetch failed'}"
            )
        ancestor = subprocess.run(
            ["git", "-C", probe, "merge-base", "--is-ancestor", pin, "refs/heads/tracked"],
            capture_output=True,
            text=True,
        )
        # 1 is the answer "no"; anything else is git saying it could not
        # work out the question, which must not read as a rollback.
        if ancestor.returncode not in (0, 1):
            raise BumpError(
                f"{repository}: cannot tell whether {branch} contains {pin}: "
                f"{ancestor.stderr.strip() or 'git merge-base failed'}"
            )
        return ancestor.returncode == 0
    finally:
        shutil.rmtree(probe, ignore_errors=True)


def rewrite_pin(text, variable, old, new):
    pattern = re.compile(
        r"(set\(\s*" + re.escape(variable) + r"_TAG\s+)" + re.escape(old) + r"(?=[\s)])"
    )
    rewritten, count = pattern.subn(lambda match: match.group(1) + new, text)
    if count != 1:
        raise BumpError(
            f"{COMPONENTS_PATH}: expected one {variable}_TAG assignment, found {count}"
        )
    return rewritten


def commit_message(moves):
    names = [move["component"] for move in moves]
    if len(names) == 1:
        subject = f"Move the {names[0]} pin to {moves[0]['new'][:9]}"
    elif len(names) == 2:
        subject = f"Move the {names[0]} and {names[1]} pins forward"
    else:
        subject = f"Move {len(names)} source pins forward"
    body = "\n".join(
        f"{move['component']} {move['branch']}: {move['old'][:9]} -> {move['new'][:9]}"
        for move in moves
    )
    return f"{subject}\n\n{body}\n"


def bump(components_path, tracking_path, overrides, dry_run):
    try:
        with open(components_path, encoding="utf-8") as handle:
            text = handle.read()
    except OSError as exc:
        raise BumpError(f"{components_path} cannot be read: {exc}") from exc

    components = parse_components(text)
    tracked = load_tracking(tracking_path, components)

    moves = []
    for name in sorted(tracked):
        component = components[name]
        repository = overrides.get(name, component["repository"])
        head = resolve_branch(repository, tracked[name])
        if head == component["pin"]:
            continue
        if not contains(repository, component["pin"], tracked[name]):
            raise BumpError(
                f"{name}: {tracked[name]} is at {head}, which does not contain "
                f"the pinned {component['pin']}; moving it would roll the "
                "source back"
            )
        text = rewrite_pin(text, component["variable"], component["pin"], head)
        moves.append(
            {
                "component": name,
                "branch": tracked[name],
                "old": component["pin"],
                "new": head,
            }
        )

    if moves and not dry_run:
        with open(components_path, "w", encoding="utf-8") as handle:
            handle.write(text)
    return moves


def main(argv):
    parser = argparse.ArgumentParser(prog="bump-pins")
    parser.add_argument("--components", default=COMPONENTS_PATH)
    parser.add_argument("--tracking", default=TRACKING_PATH)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--message-file")
    parser.add_argument(
        "--repository",
        action="append",
        default=[],
        metavar="COMPONENT=URL",
        help="resolve one component somewhere else than Components.cmake says",
    )
    args = parser.parse_args(argv)

    overrides = {}
    for override in args.repository:
        name, separator, url = override.partition("=")
        if not separator or not name or not url:
            print(f"bump-pins: --repository wants COMPONENT=URL, got {override}", file=sys.stderr)
            return 1
        overrides[name] = url

    try:
        moves = bump(args.components, args.tracking, overrides, args.dry_run)
    except BumpError as exc:
        print(f"bump-pins: {exc}", file=sys.stderr)
        return 1

    for move in moves:
        print(f"{move['component']} {move['branch']}: {move['old']} -> {move['new']}")
    print(f"bump-pins: {len(moves)} pin(s) moved" if moves else "bump-pins: nothing moved")

    if args.message_file:
        message = commit_message(moves) if moves else ""
        with open(args.message_file, "w", encoding="utf-8") as handle:
            handle.write(message)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
