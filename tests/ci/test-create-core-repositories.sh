#!/usr/bin/env bash
# Contract test for scripts/create-core-repositories.sh: the grouped
# repository behavior ported from vitasdk/autobuilds (reproducibility,
# client-dependency enforcement, corruption detection) plus this workflow's
# addition, release.json -- shape owned by `verify` (next-refactor-verify),
# produced here.

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/vitasdk-buildscripts-repository.XXXXXXXX")
pacman_image='archlinux@sha256:c1829f370be8434135f43fb3acaef1256780804ac3b2d2eec90dfb1232e1ffdf'

cleanup() {
	chmod -R u+rwX "$temporary_root" 2>/dev/null || true
	rm -rf -- "$temporary_root"
}
trap cleanup EXIT

# Provenance echoes: written the same way scripts/ci/lib.sh's
# ci_write_provenance writes them, into artifact-style stage<N>-<host>
# directories, since create-core-repositories.sh parses that exact layout
# without a JSON library (the grouping job runs inside a bare archlinux
# container that carries no python3).
write_provenance() {
	local dir=$1 host=$2 build_id=$3
	shift 3
	mkdir -p "$dir"
	python3 - "$dir/provenance.json" "$host" "$build_id" "$@" <<'PY'
import json, sys
out, host, build_id, *artifacts = sys.argv[1:]
json.dump({"host": host, "build_id": build_id, "artifacts": artifacts}, open(out, "w"), indent=2, sort_keys=True)
PY
}
write_provenance "$temporary_root/provenance/stage2-x86_64-linux-gnu" \
	x86_64-linux-gnu 'sha256:deadbeef' vitasdk-core-0.1-1-x86_64-linux-gnu.pkg.tar.xz
write_provenance "$temporary_root/provenance/stage2-aarch64-linux-gnu" \
	aarch64-linux-gnu 'sha256:deadbeef' vitasdk-core-0.1-1-aarch64-linux-gnu.pkg.tar.xz
# A decoy: x86_64-linux-gnu also has a stage-1 (sysroot-only) provenance
# echo with a *different* build_id. If the stage-1 exclusion in
# provenance_build_id_for_host regresses, this makes the test catch it by
# tripping the release.json build_id assertion below.
write_provenance "$temporary_root/provenance/stage1-x86_64-linux-gnu" \
	x86_64-linux-gnu 'sha256:stage1-decoy' vitasdk-sysroot-fixture.tar.bz2

docker run --rm \
	--platform linux/amd64 \
	--mount "type=bind,source=$repository_root,target=/workspace,readonly" \
	--mount "type=bind,source=$temporary_root,target=/work" \
	--env SOURCE_DATE_EPOCH=1700000000 \
	--env RELEASE_SCHEMA=1 \
	--env RELEASE_BUILD_ID=sha256:deadbeef \
	--env RELEASE_BUILDSCRIPTS_REVISION=0123456789abcdef0123456789abcdef01234567 \
	--env RELEASE_PROFILE=vita \
	--env RELEASE_PROVENANCE_DIRECTORY=/work/provenance \
	"$pacman_image" \
	bash -euc '
		export LC_ALL=C
		create_package() {
			local architecture=$1 name=$2 depends=$3 payload=$4
			local root="/work/package-$name-$architecture"
			local output="/work/$name-0.1-1-$architecture.pkg.tar.xz"
			install -d "$root/bin"
			printf "#!/bin/sh\nexit 0\n" > "$root/bin/$payload"
			chmod +x "$root/bin/$payload"
			cat > "$root/.PKGINFO" <<EOF
pkgname = $name
pkgbase = $name
pkgver = 0.1-1
pkgdesc = VitaSDK core repository fixture
url = https://vitasdk.org/
builddate = 1700000000
packager = VitaSDK Tests
size = 32
arch = $architecture
license = custom
xdata = pkgtype=pkg
EOF
			[ -z "$depends" ] || printf "depend = %s\n" "$depends" >> "$root/.PKGINFO"
			printf "format = 2\n" > "$root/.BUILDINFO"
			(
				cd "$root"
				find . -mindepth 1 ! -name .MTREE -print0 | sort -z |
					bsdtar -cnf - --format=mtree \
						--options="!all,use-set,type,uid,gid,mode,time,size,sha256,link" \
						--uid 0 --gid 0 --null -T - | gzip -n > .MTREE
				find . -exec touch -h -d @1700000000 {} +
				find . -mindepth 1 -printf "%P\n" | sort |
					bsdtar --format=gnutar --uid 0 --gid 0 \
						--uname root --gname root -cnf - -T - | xz -9 -c > "$output"
			)
		}

		for architecture in x86_64-linux-gnu aarch64-linux-gnu; do
			create_package "$architecture" vdpm "" vdpm
			create_package "$architecture" vitasdk-core "vdpm>=0.1-1" \
				arm-vita-eabi-gcc
		done
		mkdir /work/sdk-archives
		printf "bootstrap fixture\n" > \
			/work/sdk-archives/vitasdk-bootstrap-x86_64-linux-gnu.tar.bz2
		printf "bootstrap fixture\n" > \
			/work/sdk-archives/vitasdk-bootstrap-aarch64-linux-gnu.tar.bz2
		printf "compatibility fixture\n" > \
			/work/sdk-archives/vitasdk-x86_64-linux-gnu-fixture.tar.bz2
		# The tarball stage 1 produces must never reach the published tree:
		# it is not a host SDK, just an internal artifact of that stage
		printf "sysroot fixture\n" > \
			/work/sdk-archives/vitasdk-sysroot-20260822_000000.tar.bz2
		packages=(/work/*-0.1-1-*.pkg.tar.xz)
		export SDK_ARCHIVE_DIRECTORY=/work/sdk-archives
		/workspace/scripts/create-core-repositories.sh \
			/work/repository-one "${packages[@]}"
		/workspace/scripts/create-core-repositories.sh \
			/work/repository-two "${packages[@]}"
		diff -ru /work/repository-one /work/repository-two
		test -f /work/repository-one/vitasdk-bootstrap-x86_64-linux-gnu.tar.bz2
		if [ -e /work/repository-one/vitasdk-sysroot-20260822_000000.tar.bz2 ]; then
			printf "the stage-1 sysroot tarball leaked into the published tree\n" >&2
			exit 1
		fi

		# release.json exists, is covered by SHA256SUMS like every other
		# published file, and echoes what each host reported.
		test -f /work/repository-one/release.json
		if ! grep -q release.json /work/repository-one/SHA256SUMS; then
			printf "release.json must be covered by SHA256SUMS\n" >&2
			exit 1
		fi
		python3 -c "
import json
manifest = json.load(open(\"/work/repository-one/release.json\"))
assert manifest[\"schema\"] == 1, manifest
assert manifest[\"build_id\"] == \"sha256:deadbeef\", manifest
assert manifest[\"buildscripts_revision\"] == \"0123456789abcdef0123456789abcdef01234567\", manifest
assert manifest[\"profile\"] == \"vita\", manifest
hosts = {h[\"name\"]: h for h in manifest[\"hosts\"]}
assert set(hosts) == {\"x86_64-linux-gnu\", \"aarch64-linux-gnu\"}, hosts
for name, host in hosts.items():
    assert host[\"build_id\"] == \"sha256:deadbeef\", host
    assert f\"{name}.db\" in host[\"artifacts\"], host
    assert f\"vitasdk-bootstrap-{name}.tar.bz2\" in host[\"artifacts\"], host
    assert any(a.startswith(\"vitasdk-core-\") for a in host[\"artifacts\"]), host
print(\"release.json contract passed\")
"

		cat > /work/pacman.conf <<EOF
[options]
Architecture = x86_64-linux-gnu vita
SigLevel = Never
[x86_64-linux-gnu]
Server = file:///work/repository-one
EOF
		install -d /sdk/var/lib/pacman /sdk/var/cache/pacman/pkg
		pacman --config /work/pacman.conf --root /sdk \
			--dbpath /sdk/var/lib/pacman --cachedir /sdk/var/cache/pacman/pkg \
			--logfile /sdk/var/log/pacman.log --noscriptlet \
			--sync --refresh --refresh --noconfirm
		pacman --config /work/pacman.conf --root /sdk \
			--dbpath /sdk/var/lib/pacman --cachedir /sdk/var/cache/pacman/pkg \
			--logfile /sdk/var/log/pacman.log --noscriptlet \
			--sync --noconfirm vitasdk-core
		test -x /sdk/bin/arm-vita-eabi-gcc
		test -x /sdk/bin/vdpm
		pacman --config /work/pacman.conf --root /sdk \
			--dbpath /sdk/var/lib/pacman --query vdpm

		core_only=(/work/vitasdk-core-0.1-1-*.pkg.tar.xz)
		if /workspace/scripts/create-core-repositories.sh \
			/work/repository-without-client "${core_only[@]}" 2>/dev/null; then
			printf "a repository without the client was unexpectedly built\n" >&2
			exit 1
		fi

		# A published architecture with no provenance echo is a grouping bug,
		# not a build_id mismatch (verify checks that); catch it here.
		rm -rf /work/provenance-partial
		mkdir -p /work/provenance-partial
		cp -a /work/provenance/stage2-x86_64-linux-gnu /work/provenance-partial/
		if RELEASE_PROVENANCE_DIRECTORY=/work/provenance-partial \
			/workspace/scripts/create-core-repositories.sh \
			/work/repository-missing-provenance "${packages[@]}" 2>/dev/null; then
			printf "grouping without a full provenance set was unexpectedly accepted\n" >&2
			exit 1
		fi
	'

printf 'VitaSDK grouped core repository contracts passed\n'
