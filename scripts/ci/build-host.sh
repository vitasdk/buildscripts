#!/usr/bin/env bash
# Entry point the reusable build workflow invokes for one (stage, host) pair.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
# shellcheck source=scripts/ci/lib.sh
source "$repo_root/scripts/ci/lib.sh"

host=""
stage=""
artifacts_dir=""
out_dir=""
build_id=""
version=""
revision=""
profile=""
packaged=""
build_host=""

while [[ $# -gt 0 ]]; do
	case $1 in
	--host)
		host=$2
		shift 2
		;;
	--stage)
		stage=$2
		shift 2
		;;
	--artifacts-dir)
		artifacts_dir=$2
		shift 2
		;;
	--out-dir)
		out_dir=$2
		shift 2
		;;
	--build-id)
		build_id=$2
		shift 2
		;;
	--version)
		version=$2
		shift 2
		;;
	--revision)
		revision=$2
		shift 2
		;;
	--profile)
		profile=$2
		shift 2
		;;
	--packaged)
		packaged=$2
		shift 2
		;;
	--build-host)
		build_host=$2
		shift 2
		;;
	*)
		printf 'unknown argument: %s\n' "$1" >&2
		exit 2
		;;
	esac
done
for required in host stage artifacts_dir out_dir build_id version revision profile packaged; do
	[[ -n ${!required} ]] || {
		printf -- '--%s is required\n' "${required//_/-}" >&2
		exit 2
	}
done
# profile is required but not yet consumed: no profile -> VITASDK_FLOAT_ABI
# mapping exists in CMakeLists.txt yet.
: "$profile"

actual_revision=$(git -C "$repo_root" rev-parse HEAD)
[[ $actual_revision == "$revision" ]] || {
	printf 'checked out %s but the lock names %s\n' "$actual_revision" "$revision" >&2
	exit 1
}
source_date_epoch=$(git -C "$repo_root" show -s --format=%ct HEAD)

mkdir -p "$out_dir"
export LANG=C.UTF-8
git config --global user.email "builds@ci.invalid"
git config --global user.name "buildscripts CI"

# The matrix's packaged flag, not the host name, gates core-package treatment.
is_packaged_host() { [[ $packaged == true ]]; }

vdpm_tag() {
	sed -n 's/^set(VDPM_TAG \([^ )]*\).*/\1/p' "$repo_root/cmake/Components.cmake"
}

# Sets vdpm_bundle/vdpm_bundle_sha256. Verified against the release's own
# sidecar checksum, not a hash pinned in Components.cmake (source pinning is
# out of this workflow's scope).
download_vdpm_bundle() {
	local vdpm_host=$1 dest_dir=$2 tag archive base actual sidecar
	mkdir -p "$dest_dir"
	tag=$(vdpm_tag)
	archive="vdpm-${tag#v}-$vdpm_host.tar.bz2"
	base="https://github.com/vitasdk/vdpm/releases/download/$tag"
	curl -fsSL --retry 3 -o "$dest_dir/$archive" "$base/$archive"
	curl -fsSL --retry 3 -o "$dest_dir/$archive.sha256" "$base/$archive.sha256"
	actual=$(ci_sha256 "$dest_dir/$archive")
	sidecar=$(awk '{print $1}' "$dest_dir/$archive.sha256")
	[[ $actual == "$sidecar" ]] || {
		printf 'vdpm bundle hash mismatch for %s\n' "$vdpm_host" >&2
		return 1
	}
	vdpm_bundle="$dest_dir/$archive"
	vdpm_bundle_sha256=$actual
}

# Same-runner smoke test only; a canadian cross cannot run what it built.
smoke_test_bootstrap() {
	local bootstrap_archive=$1 digest install_root
	digest=$(awk '{print $1}' "$bootstrap_archive.sha256")
	install_root="$PWD/bootstrap-installed"
	VITASDK_BOOTSTRAP_ARCHIVE="$bootstrap_archive" VITASDK_BOOTSTRAP_SHA256="$digest" \
		build/vitasdk/share/vdpm/bootstrap-vitasdk.sh --install-dir "$install_root"
	VITASDK="$install_root" "$install_root/bin/vdpm" --help >/dev/null
	# vdpm ships pacman under libexec/vdpm, not bin/.
	"$install_root/libexec/vdpm/pacman" --version >/dev/null
	"$install_root/bin/arm-vita-eabi-gcc" --version
}

# Builds against $stage1_dir if set, then stages outputs plus provenance.
build_and_stage() {
	# ${arr[@]+...}: macOS's /bin/bash is 3.2, where expanding an empty
	# array under set -u is an unbound-variable error.
	local -a extra_args=("$@")
	local -a cmake_args=(
		-S "$repo_root" -B build ${extra_args[@]+"${extra_args[@]}"}
		-DVITASDK_SOURCE_REVISION="$revision"
		-DVITASDK_SOURCE_DATE_EPOCH="$source_date_epoch"
	)
	[[ -n ${stage1_dir:-} ]] && cmake_args+=(-DVITASDK_STAGE1_DIR="$stage1_dir")
	local -a targets=(tarball)

	local vdpm_bundle="" vdpm_bundle_sha256=""
	if is_packaged_host; then
		download_vdpm_bundle "$host" "$PWD/vdpm-release"
		cmake_args+=(
			-DBUILD_PACMAN_CLIENT=ON
			-DVITASDK_PACKAGE_VERSION="$version"
			-DVDPM_BUNDLE="$vdpm_bundle"
			-DVDPM_BUNDLE_SHA256="$vdpm_bundle_sha256"
		)
		targets+=(core-package bootstrap-archive)
	fi

	cmake "${cmake_args[@]}"
	cmake --build build --target "${targets[@]}" --parallel "$(ci_nproc)"

	# Only a native build can run its own output.
	if [[ -z $build_host ]]; then
		cmake --build build --target check-toolchain-contract
		if is_packaged_host; then
			smoke_test_bootstrap "build/bootstraps/vitasdk-bootstrap-$host.tar.bz2"
		fi
	fi

	local -a produced=(build/vitasdk-*.tar.bz2)
	if is_packaged_host; then
		produced+=(build/packages/*.pkg.tar.xz build/bootstraps/vitasdk-bootstrap-*.tar.bz2 build/bootstraps/vitasdk-bootstrap-*.tar.bz2.sha256)
	fi
	local -a names=()
	local file
	for file in "${produced[@]}"; do
		[[ -f $file ]] || continue
		cp "$file" "$out_dir/"
		names+=("$(basename "$file")")
	done
	# The globs skip silently, so a packaged host that produced nothing of a
	# family would otherwise publish a quietly incomplete provenance.
	if is_packaged_host; then
		local pattern
		for pattern in 'vitasdk-core-*.pkg.tar.xz' 'vdpm-*.pkg.tar.xz' \
			"vitasdk-bootstrap-$host.tar.bz2" "vitasdk-bootstrap-$host.tar.bz2.sha256"; do
			printf '%s\n' ${names[@]+"${names[@]}"} | grep -x -- "${pattern//\*/.*}" >/dev/null || {
				printf 'packaged host %s produced no %s\n' "$host" "$pattern" >&2
				exit 1
			}
		done
	fi
	ci_write_provenance "$out_dir" "$host" "$build_id" ${names[@]+"${names[@]}"}
}

# musl hosts are native builds inside Alpine (see build.yml stage2-musl).
build_musl_host() {
	docker run --rm \
		-v "$PWD":/src -w /src \
		-e VITASDK_SOURCE_REVISION="$revision" \
		-e VITASDK_SOURCE_DATE_EPOCH="$source_date_epoch" \
		alpine:3.20 sh -eux -c '
			apk add --no-cache bash build-base cmake git autoconf automake \
				libtool texinfo bison flex pkgconf curl xz python3 bzip2 \
				tar linux-headers
			git config --global --add safe.directory "*"
			git config --global user.email "builds@ci.invalid"
			git config --global user.name "buildscripts CI"
			STAGE1_DIR=$(dirname "$(dirname "$(dirname "$(find /src/stage1 -type f -path "*/arm-vita-eabi/lib/libc.a" | head -1)")")")
			test -n "$STAGE1_DIR"
			mkdir -p /src/build
			cd /src/build
			cmake /src -DVITASDK_STAGE1_DIR="$STAGE1_DIR" \
				-DVITASDK_SOURCE_REVISION="$VITASDK_SOURCE_REVISION" \
				-DVITASDK_SOURCE_DATE_EPOCH="$VITASDK_SOURCE_DATE_EPOCH"
			make -j"$(getconf _NPROCESSORS_ONLN)" tarball
			make check-toolchain-contract
		'
	local -a produced=(build/vitasdk-*.tar.bz2)
	local -a names=()
	local file
	for file in "${produced[@]}"; do
		[[ -f $file ]] || continue
		cp "$file" "$out_dir/"
		names+=("$(basename "$file")")
	done
	ci_write_provenance "$out_dir" "$host" "$build_id" "${names[@]}"
}

install_dependencies() {
	local sudo_cmd=()
	[[ $(id -u) == 0 ]] || sudo_cmd=(sudo)
	case "$(uname -s)" in
	Darwin)
		brew install autoconf automake libtool texinfo
		;;
	Linux)
		local -a extra=()
		case $host in
		x86_64-w64-mingw32) extra=(g++-mingw-w64-x86-64) ;;
		i686-w64-mingw32) extra=(g++-mingw-w64-i686) ;;
		x86_64-unknown-freebsd | aarch64-unknown-freebsd) extra=(clang lld llvm) ;;
		esac
		"${sudo_cmd[@]}" apt-get update -qq
		"${sudo_cmd[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
			cmake cmake-data git build-essential autoconf automake libtool \
			texinfo bison flex pkg-config python3 python3-pip curl bzip2 xz-utils \
			libarchive-tools \
			"${extra[@]}"
		pip3 install --quiet cmake==3.31.6
		;;
	esac
}

if [[ $stage == 1 ]]; then
	# Dispatch is on stage, not host name: the lock may reuse a name here
	# (e.g. x86_64-linux-gnu) that also appears at stage 2.
	install_dependencies
	cmake -S "$repo_root" -B build \
		-DVITASDK_TARGET_ONLY=ON \
		-DVITASDK_SOURCE_REVISION="$revision" \
		-DVITASDK_SOURCE_DATE_EPOCH="$source_date_epoch"
	cmake --build build --target sysroot --parallel "$(ci_nproc)"
	cp build/vitasdk-sysroot-*.tar.bz2 "$out_dir/"
	ci_write_provenance "$out_dir" "$host" "$build_id" "$(basename build/vitasdk-sysroot-*.tar.bz2)"
	exit 0
fi

if [[ $host == *-linux-musl ]]; then
	# The musl path builds only the SDK tarball; flipping packaged on must
	# fail here rather than publish a host with no packages or bootstrap.
	if is_packaged_host; then
		printf 'packaged musl hosts are not implemented\n' >&2
		exit 1
	fi
	stage1_source_dir=$(ci_find_stage_artifact "$artifacts_dir" 1 '*') ||
		{
			printf 'stage1 artifact not found under %s\n' "$artifacts_dir" >&2
			exit 1
		}
	ci_unpack_sdk_artifact "$stage1_source_dir" "$PWD/stage1"
	build_musl_host
	exit 0
fi

extra_cmake_args=()
case $host in
x86_64-linux-gnu | aarch64-linux-gnu | arm64-apple-darwin)
	install_dependencies
	;;
x86_64-w64-mingw32)
	install_dependencies
	extra_cmake_args+=(-DCMAKE_TOOLCHAIN_FILE="$repo_root/cmake/toolchains/x86_64-w64-mingw32.cmake")
	;;
i686-w64-mingw32)
	install_dependencies
	extra_cmake_args+=(-DCMAKE_TOOLCHAIN_FILE="$repo_root/cmake/toolchains/i686-w64-mingw32.cmake")
	;;
x86_64-unknown-freebsd)
	install_dependencies
	scripts/setup-freebsd-cross.sh 14.3 "$PWD/freebsd-cross" x86_64
	export PATH="$PWD/freebsd-cross/bin:$PATH"
	extra_cmake_args+=(-DCMAKE_TOOLCHAIN_FILE="$repo_root/cmake/toolchains/x86_64-unknown-freebsd.cmake")
	;;
aarch64-unknown-freebsd)
	install_dependencies
	scripts/setup-freebsd-cross.sh 14.3 "$PWD/freebsd-cross" aarch64
	export PATH="$PWD/freebsd-cross/bin:$PATH"
	extra_cmake_args+=(-DCMAKE_TOOLCHAIN_FILE="$repo_root/cmake/toolchains/aarch64-unknown-freebsd.cmake")
	;;
x86_64-apple-darwin)
	install_dependencies
	scripts/setup-macos-cross.sh "$PWD/macos-cross"
	export PATH="$PWD/macos-cross/bin:$PATH"
	extra_cmake_args+=(-DCMAKE_TOOLCHAIN_FILE="$repo_root/cmake/toolchains/x86_64-apple-darwin.cmake")
	;;
*)
	printf 'no build recipe for host: %s\n' "$host" >&2
	exit 1
	;;
esac

if [[ $stage == 2 ]]; then
	# Whichever host name produced stage 1 -- see the dispatch note above.
	stage1_source_dir=$(ci_find_stage_artifact "$artifacts_dir" 1 '*') ||
		{
			printf 'stage1 artifact not found under %s\n' "$artifacts_dir" >&2
			exit 1
		}
	ci_unpack_sdk_artifact "$stage1_source_dir" "$PWD/stage1"
	stage1_dir=$(ci_find_sdk_root "$PWD/stage1")
else
	# Always stage 2 (a full SDK, with arm-vita-eabi-gcc for -dumpspecs),
	# even for a host name that also has a stage-1 entry. build_host comes
	# from the lock (cmake/hosts.json), not a hardcoded per-host table.
	[[ -n $build_host ]] || {
		printf 'stage 3 host %s has no build-machine mapping\n' "$host" >&2
		exit 1
	}
	build_sdk_source_dir=$(ci_find_stage_artifact "$artifacts_dir" 2 "$build_host") ||
		{
			printf 'no build-machine SDK found for %s (needs %s)\n' "$host" "$build_host" >&2
			exit 1
		}
	ci_unpack_sdk_artifact "$build_sdk_source_dir" "$PWD/build-sdk"
	stage1_dir=$(ci_find_sdk_root "$PWD/build-sdk")
	export PATH="$stage1_dir/bin:$PATH"
fi

build_and_stage ${extra_cmake_args[@]+"${extra_cmake_args[@]}"}
