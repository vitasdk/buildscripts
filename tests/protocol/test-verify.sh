#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
cli="$repository_root/buildscripts-ci"
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/buildscripts-verify.XXXXXXXX")
cleanup() { rm -rf -- "$temporary_root"; }
trap cleanup EXIT

sha256_of() {
	if command -v sha256sum >/dev/null; then
		sha256sum "$1" | awk '{print $1}'
	else
		shasum -a 256 "$1" | awk '{print $1}'
	fi
}

# verify never opens packages, so synthetic placeholder files are enough.
build_valid_tree() {
	local tree=$1
	mkdir -p "$tree"
	printf 'core\n' > "$tree/vitasdk-core-0.1-1-x86_64-linux-gnu.pkg.tar.xz"
	printf 'client\n' > "$tree/vdpm-0.1.0-1-x86_64-linux-gnu.pkg.tar.xz"
	printf 'db\n' > "$tree/x86_64-linux-gnu.db"
	printf 'files\n' > "$tree/x86_64-linux-gnu.files"
	printf 'bootstrap\n' > "$tree/vitasdk-bootstrap-x86_64-linux-gnu.tar.bz2"
	printf 'core\n' > "$tree/vitasdk-core-0.1-1-x86_64-w64-mingw32.pkg.tar.xz"
	printf 'client\n' > "$tree/vdpm-0.1.0-1-x86_64-w64-mingw32.pkg.tar.xz"
	printf 'db\n' > "$tree/x86_64-w64-mingw32.db"
	printf 'files\n' > "$tree/x86_64-w64-mingw32.files"
	printf 'bootstrap\n' > "$tree/vitasdk-bootstrap-x86_64-w64-mingw32.tar.bz2"

	cat > "$tree/release.json" <<'EOF'
{
  "schema": 1,
  "build_id": "sha256:test-build-id",
  "buildscripts_revision": "0123456789abcdef0123456789abcdef01234567",
  "profile": "vita",
  "hosts": [
    {
      "name": "x86_64-linux-gnu",
      "build_id": "sha256:test-build-id",
      "artifacts": [
        "vitasdk-core-0.1-1-x86_64-linux-gnu.pkg.tar.xz",
        "vdpm-0.1.0-1-x86_64-linux-gnu.pkg.tar.xz",
        "x86_64-linux-gnu.db",
        "x86_64-linux-gnu.files",
        "vitasdk-bootstrap-x86_64-linux-gnu.tar.bz2"
      ]
    },
    {
      "name": "x86_64-w64-mingw32",
      "build_id": "sha256:test-build-id",
      "artifacts": [
        "vitasdk-core-0.1-1-x86_64-w64-mingw32.pkg.tar.xz",
        "vdpm-0.1.0-1-x86_64-w64-mingw32.pkg.tar.xz",
        "x86_64-w64-mingw32.db",
        "x86_64-w64-mingw32.files",
        "vitasdk-bootstrap-x86_64-w64-mingw32.tar.bz2"
      ]
    }
  ]
}
EOF

	: > "$tree/SHA256SUMS"
	(
		cd "$tree"
		for asset in *; do
			[[ $asset == SHA256SUMS ]] && continue
			printf '%s  %s\n' "$(sha256_of "$asset")" "$asset" >> SHA256SUMS
		done
	)
}

# $2 is a Python statement applied to release.json's parsed data (as `data`).
edit_manifest() {
	local tree=$1 expression=$2
	python3 - "$tree/release.json" "$expression" <<'PYEOF'
import json
import sys

path, expression = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as handle:
	data = json.load(handle)
exec(expression)
with open(path, "w", encoding="utf-8") as handle:
	json.dump(data, handle, indent=2)
PYEOF
}

assert_fails() {
	local description=$1 tree=$2 expected_substring=$3
	local output status
	output=$("$cli" verify --tree "$tree" 2>&1) && status=0 || status=$?
	if [[ $status -eq 0 ]]; then
		printf 'expected failure (%s), verify exited 0\n' "$description" >&2
		exit 1
	fi
	if [[ $output != *"$expected_substring"* ]]; then
		printf 'expected failure (%s) to mention %q, got: %s\n' \
			"$description" "$expected_substring" "$output" >&2
		exit 1
	fi
}

valid_tree="$temporary_root/valid"
build_valid_tree "$valid_tree"
output=$("$cli" verify --tree "$valid_tree")
[[ $output == *"hosts=2"* && $output == *"artifacts=10"* ]] || {
	printf 'unexpected success output: %s\n' "$output" >&2
	exit 1
}

assert_fails "nonexistent tree" "$temporary_root/does-not-exist" "not found"

no_manifest="$temporary_root/no-manifest"
build_valid_tree "$no_manifest"
rm -f "$no_manifest/release.json"
assert_fails "missing manifest" "$no_manifest" "missing release manifest"

bad_json="$temporary_root/bad-json"
build_valid_tree "$bad_json"
printf 'not json' > "$bad_json/release.json"
assert_fails "malformed manifest" "$bad_json" "not valid JSON"

bad_schema="$temporary_root/bad-schema"
build_valid_tree "$bad_schema"
edit_manifest "$bad_schema" 'data["schema"] = 2'
assert_fails "unsupported schema" "$bad_schema" "tree declares 2, this verify supports 1"

mismatched_build_id="$temporary_root/mismatched-build-id"
build_valid_tree "$mismatched_build_id"
edit_manifest "$mismatched_build_id" 'data["hosts"][0]["build_id"] = "sha256:other"'
assert_fails "build_id mismatch" "$mismatched_build_id" "echoes build_id"

missing_artifact="$temporary_root/missing-artifact"
build_valid_tree "$missing_artifact"
rm -f "$missing_artifact/vdpm-0.1.0-1-x86_64-linux-gnu.pkg.tar.xz"
assert_fails "missing artifact" "$missing_artifact" \
	"missing declared artifacts: vdpm-0.1.0-1-x86_64-linux-gnu.pkg.tar.xz"

extra_file="$temporary_root/extra-file"
build_valid_tree "$extra_file"
printf 'surprise\n' > "$extra_file/unexpected-file.txt"
assert_fails "undeclared file" "$extra_file" "undeclared files present: unexpected-file.txt"

bad_checksum="$temporary_root/bad-checksum"
build_valid_tree "$bad_checksum"
printf 'tampered\n' > "$bad_checksum/vitasdk-core-0.1-1-x86_64-linux-gnu.pkg.tar.xz"
assert_fails "checksum mismatch" "$bad_checksum" "checksum mismatch for vitasdk-core-0.1-1-x86_64-linux-gnu.pkg.tar.xz"

path_traversal="$temporary_root/path-traversal"
build_valid_tree "$path_traversal"
edit_manifest "$path_traversal" 'data["hosts"][0]["artifacts"][2] = "../escape"'
assert_fails "path traversal artifact" "$path_traversal" "not a safe relative path"

nested_dir="$temporary_root/nested-dir"
build_valid_tree "$nested_dir"
mkdir "$nested_dir/subdir"
assert_fails "nested directory" "$nested_dir" "non-regular entry: subdir"

printf 'buildscripts-ci verify contract passed\n'
