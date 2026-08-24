#!/usr/bin/env bash
# Argument-contract tests for scripts/ci/build-host.sh: the packaged/build_host
# wiring that replaced the internal is_required_host list and the per-host
# build_sdk_host table. Stops short of a real build (needs a full toolchain).

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/buildscripts-build-host-args.XXXXXXXX")
cleanup() { rm -rf -- "$temporary_directory"; }
trap cleanup EXIT

# A fake uname keeps install_dependencies() a no-op (neither Darwin nor
# Linux matches) so this test never touches apt/brew/network. A redirected
# HOME keeps the script's `git config --global` off the real machine config.
fake_bin="$temporary_directory/bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/uname" <<'EOF'
#!/usr/bin/env bash
echo TestOS
EOF
chmod +x "$fake_bin/uname"
fake_home="$temporary_directory/home"
mkdir -p "$fake_home"

revision=$(git -C "$repository_root" rev-parse HEAD)

run_build_host() {
	PATH="$fake_bin:$PATH" HOME="$fake_home" \
		bash "$repository_root/scripts/ci/build-host.sh" "$@"
}

# 1. A missing required flag fails fast, naming it.
if output=$(run_build_host \
	--host x86_64-linux-gnu --stage 2 \
	--artifacts-dir "$temporary_directory/artifacts" --out-dir "$temporary_directory/out" \
	--build-id sha256:test --version 0.1.1 --revision "$revision" --profile vita 2>&1); then
	printf 'build-host.sh accepted a run with no --packaged\n' >&2
	exit 1
fi
grep -q -- '--packaged is required' <<< "$output" || {
	printf 'build-host.sh did not name the missing --packaged flag: %s\n' "$output" >&2
	exit 1
}

# 2. A packaged stage-3 host with no --build-host fails: the build machine
# comes from the lock now, not a hardcoded per-host table.
if output=$(run_build_host \
	--host x86_64-w64-mingw32 --stage 3 \
	--artifacts-dir "$temporary_directory/artifacts-2" --out-dir "$temporary_directory/out-2" \
	--build-id sha256:test --version 0.1.1 --revision "$revision" --profile vita \
	--packaged true 2>&1); then
	printf 'build-host.sh accepted a stage-3 host with no --build-host\n' >&2
	exit 1
fi
grep -q 'has no build-machine mapping' <<< "$output" || {
	printf 'build-host.sh did not name the missing build-machine mapping: %s\n' "$output" >&2
	exit 1
}

# 3. A given --build-host is what gets looked up, not an internal default:
# an artifacts dir with no matching stage2-<build-host> directory fails,
# naming the exact value passed in.
if output=$(run_build_host \
	--host x86_64-w64-mingw32 --stage 3 \
	--artifacts-dir "$temporary_directory/artifacts-3" --out-dir "$temporary_directory/out-3" \
	--build-id sha256:test --version 0.1.1 --revision "$revision" --profile vita \
	--packaged true --build-host some-other-host 2>&1); then
	printf 'build-host.sh accepted a --build-host with no matching artifact\n' >&2
	exit 1
fi
grep -q 'needs some-other-host' <<< "$output" || {
	printf 'build-host.sh did not name the requested build-host: %s\n' "$output" >&2
	exit 1
}

printf 'build-host.sh argument contract tests passed\n'
