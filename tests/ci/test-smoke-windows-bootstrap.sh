#!/usr/bin/env bash
# Contract tests for scripts/ci/smoke-windows-bootstrap.ps1's local decision
# logic (no-op vs. fail) -- the parts reachable without a real Windows
# runner or a real bootstrap archive.

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
script="$repository_root/scripts/ci/smoke-windows-bootstrap.ps1"
command -v pwsh >/dev/null || {
	printf 'pwsh is required to run this test\n' >&2
	exit 1
}

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/vitasdk-smoke-windows-bootstrap.XXXXXXXX")
cleanup() { rm -rf -- "$temporary_root"; }
trap cleanup EXIT

host=x86_64-w64-mingw32

# 1. No artifacts directory at all: clean no-op.
if ! output=$(pwsh -NoProfile -File "$script" -ArtifactsDir "$temporary_root/missing" 2>&1); then
	printf 'expected a clean no-op for a missing artifacts directory, got:\n%s\n' "$output" >&2
	exit 1
fi
grep -q 'nothing to smoke test' <<<"$output" || {
	printf 'expected a "nothing to smoke test" message, got:\n%s\n' "$output" >&2
	exit 1
}

# 2. An artifacts directory with no matching archive: clean no-op.
empty_dir="$temporary_root/empty"
mkdir -p "$empty_dir"
if ! output=$(pwsh -NoProfile -File "$script" -ArtifactsDir "$empty_dir" 2>&1); then
	printf 'expected a clean no-op for an empty artifacts directory, got:\n%s\n' "$output" >&2
	exit 1
fi
grep -q 'nothing to smoke test' <<<"$output" || {
	printf 'expected a "nothing to smoke test" message, got:\n%s\n' "$output" >&2
	exit 1
}

# 3. An archive with no checksum sidecar fails loudly instead of skipping it.
no_checksum_dir="$temporary_root/no-checksum/stage3-$host"
mkdir -p "$no_checksum_dir"
printf 'fixture\n' >"$no_checksum_dir/vitasdk-bootstrap-$host.tar.bz2"
if pwsh -NoProfile -File "$script" -ArtifactsDir "$temporary_root/no-checksum" >/dev/null 2>&1; then
	printf 'expected failure for an archive with no checksum sidecar\n' >&2
	exit 1
fi

# 4. Two artifact directories both claiming the Windows archive: ambiguous,
# must fail rather than silently picking one.
duplicate_root="$temporary_root/duplicate"
mkdir -p "$duplicate_root/stage3-$host" "$duplicate_root/stage3-other"
printf 'fixture\n' >"$duplicate_root/stage3-$host/vitasdk-bootstrap-$host.tar.bz2"
printf 'fixture\n' >"$duplicate_root/stage3-$host/vitasdk-bootstrap-$host.tar.bz2.sha256"
printf 'fixture\n' >"$duplicate_root/stage3-other/vitasdk-bootstrap-$host.tar.bz2"
if pwsh -NoProfile -File "$script" -ArtifactsDir "$duplicate_root" >/dev/null 2>&1; then
	printf 'expected failure for two artifact directories claiming the Windows archive\n' >&2
	exit 1
fi

printf 'smoke-windows-bootstrap.ps1 contract tests passed\n'
