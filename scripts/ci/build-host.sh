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

# An autotools component says why it refused in its config.log and nowhere
# else: the message that reaches the build log is whatever generic string the
# failing check happens to carry.
dump_configure_logs() {
	local status=$? log
	(( status == 0 )) && return 0
	while IFS= read -r log; do
		printf '::group::%s\n' "$log"
		tail -n 120 "$log"
		printf '::endgroup::\n'
	done < <(find build -name config.log -newermt '-2 hours' 2>/dev/null | head -5)
	return "$status"
}
trap dump_configure_logs EXIT

# The matrix's packaged flag, not the host name, gates core-package treatment.
is_packaged_host() { [[ $packaged == true ]]; }

# How to run this host's binaries on this machine, if at all. Prints the
# launcher prefix and succeeds; fails when there is none.
#
# What this replaces was "only a native build can run its own output", which
# is true of a canadian cross to Windows or FreeBSD and false of Apple: an
# arm64 Mac runs x86_64 Mach-O through Rosetta, so the machine that
# cross-builds the Intel SDK is also the one that can check it.
host_runner() {
	if [[ -z $build_host ]]; then
		printf ''
		return 0
	fi
	if [[ $host == x86_64-apple-darwin && $build_host == arm64-apple-darwin ]]; then
		printf 'arch -x86_64'
		return 0
	fi
	return 1
}

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
	# Empty for a host that runs here directly; a launcher for one that needs
	# it. Unquoted on purpose, so an empty prefix contributes no argument.
	local -a run=(${2:-})
	digest=$(awk '{print $1}' "$bootstrap_archive.sha256")
	install_root="$PWD/bootstrap-installed"
	# ${run[@]+...}: macOS's /bin/bash is 3.2, where expanding an empty array
	# under set -u is an unbound-variable error -- and empty is the normal
	# case here, for every host that runs its own binaries.
	VITASDK_BOOTSTRAP_ARCHIVE="$bootstrap_archive" VITASDK_BOOTSTRAP_SHA256="$digest" \
		${run[@]+"${run[@]}"} build/vitasdk/share/vdpm/bootstrap-vitasdk.sh --install-dir "$install_root"
	VITASDK="$install_root" ${run[@]+"${run[@]}"} "$install_root/bin/vdpm" --help >/dev/null
	# vdpm ships pacman under libexec/vdpm, not bin/.
	${run[@]+"${run[@]}"} "$install_root/libexec/vdpm/pacman" --version >/dev/null
	${run[@]+"${run[@]}"} "$install_root/bin/arm-vita-eabi-gcc" --version
}

# Builds against $stage1_dir if set, then stages outputs plus provenance.
build_and_stage() {
	# ${arr[@]+...}: macOS's /bin/bash is 3.2, where expanding an empty
	# array under set -u is an unbound-variable error.
	local -a extra_args=("$@")
	local -a cmake_args=(
		-S "$repo_root" -B build ${extra_args[@]+"${extra_args[@]}"}
		# The lock says which world this is; the profile is how the tree is
		# told, and it is what decides the float ABI baked into the toolchain.
		-DVITASDK_PROFILE="$profile"
		-DVITASDK_SOURCE_REVISION="$revision"
		-DVITASDK_SOURCE_DATE_EPOCH="$source_date_epoch"
		# The lock names the host; artifacts published under any other name
		# would not match what the caller asked to be built.
		-DVITASDK_HOST_NAME="$host"
		-DVITASDK_HOST_RUNNER="$(host_runner || true)"
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

	cmake ${cmake_args[@]+"${cmake_args[@]}"}
	cmake --build build --target ${targets[@]+"${targets[@]}"} --parallel "$(ci_nproc)"
	report_ccache_statistics

	# Verified wherever it can be run, which is not the same as natively.
	if runner=$(host_runner); then
		cmake --build build --target check-toolchain-contract
		if is_packaged_host; then
			smoke_test_bootstrap "build/bootstraps/vitasdk-bootstrap-$host.tar.bz2" "$runner"
		fi
	else
		printf 'no way to run %s binaries here; contract and smoke test skipped\n' "$host"
	fi

	stage_and_write_provenance
}

# Copies the standard artifact families out of ./build into $out_dir and
# writes provenance; shared by every host path (native, cross, and musl),
# all of which leave their outputs under the same build/ layout.
stage_and_write_provenance() {
	local -a produced=(build/vitasdk-*.tar.bz2)
	if is_packaged_host; then
		produced+=(build/packages/*.pkg.tar.xz build/bootstraps/vitasdk-bootstrap-*.tar.bz2 build/bootstraps/vitasdk-bootstrap-*.tar.bz2.sha256)
	fi
	local -a names=()
	local file
	for file in ${produced[@]+"${produced[@]}"}; do
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
# musl is native there -- unlike a canadian cross -- so a packaged host's
# bootstrap smoke test runs inside the same container that built it.
build_musl_host() {
	local -a docker_env=(
		-e VITASDK_HOST_NAME="$host"
		-e VITASDK_SOURCE_REVISION="$revision"
		-e VITASDK_SOURCE_DATE_EPOCH="$source_date_epoch"
		-e CCACHE_DIR=/src/.ccache
		-e CCACHE_MAXSIZE -e CCACHE_COMPRESS -e CCACHE_COMPRESSLEVEL
	)
	local vdpm_bundle="" vdpm_bundle_sha256=""
	if is_packaged_host; then
		# Downloaded here, outside the container, so it reuses the runner's
		# network/curl instead of teaching the container image about it.
		download_vdpm_bundle "$host" "$PWD/vdpm-release"
		docker_env+=(
			-e VITASDK_PACKAGED_HOST="$host"
			-e VITASDK_PACKAGE_VERSION="$version"
			-e VDPM_BUNDLE="/src/vdpm-release/$(basename "$vdpm_bundle")"
			-e VDPM_BUNDLE_SHA256="$vdpm_bundle_sha256"
		)
	fi
	# CCACHE_DIR lives under the workspace, which is already the bind mount,
	# so the container reaches the same cache the runner restored.
	docker run --rm \
		-v "$PWD":/src -w /src \
		${docker_env[@]+"${docker_env[@]}"} \
		alpine:3.20 sh -eux -c '
			apk add --no-cache bash build-base cmake git autoconf automake \
				libtool libarchive-tools texinfo bison flex pkgconf curl xz \
				python3 bzip2 tar linux-headers ccache
			export PATH="/usr/lib/ccache/bin:$PATH"
			git config --global --add safe.directory "*"
			git config --global user.email "builds@ci.invalid"
			git config --global user.name "buildscripts CI"
			STAGE1_DIR=$(dirname "$(dirname "$(dirname "$(find /src/stage1 -type f -path "*/arm-vita-eabi/lib/libc.a" | head -1)")")")
			test -n "$STAGE1_DIR"
			mkdir -p /src/build
			cd /src/build
			configure_args="-DVITASDK_STAGE1_DIR=$STAGE1_DIR -DVITASDK_SOURCE_REVISION=$VITASDK_SOURCE_REVISION -DVITASDK_SOURCE_DATE_EPOCH=$VITASDK_SOURCE_DATE_EPOCH -DVITASDK_HOST_NAME=$VITASDK_HOST_NAME"
			targets="tarball"
			if [ -n "${VITASDK_PACKAGED_HOST:-}" ]; then
				configure_args="$configure_args -DBUILD_PACMAN_CLIENT=ON -DVITASDK_PACKAGE_VERSION=$VITASDK_PACKAGE_VERSION -DVDPM_BUNDLE=$VDPM_BUNDLE -DVDPM_BUNDLE_SHA256=$VDPM_BUNDLE_SHA256"
				targets="$targets core-package bootstrap-archive"
			fi
			cmake /src $configure_args
			make -j"$(getconf _NPROCESSORS_ONLN)" $targets
			make check-toolchain-contract
			ccache --show-stats || true
			if [ -n "${VITASDK_PACKAGED_HOST:-}" ]; then
				bootstrap_archive="bootstraps/vitasdk-bootstrap-$VITASDK_PACKAGED_HOST.tar.bz2"
				bootstrap_digest=$(awk "{print \$1}" "$bootstrap_archive.sha256")
				install_root=/src/build/bootstrap-installed
				VITASDK_BOOTSTRAP_ARCHIVE="$bootstrap_archive" VITASDK_BOOTSTRAP_SHA256="$bootstrap_digest" \
					vitasdk/share/vdpm/bootstrap-vitasdk.sh --install-dir "$install_root"
				VITASDK="$install_root" "$install_root/bin/vdpm" --help >/dev/null
				"$install_root/libexec/vdpm/pacman" --version >/dev/null
				"$install_root/bin/arm-vita-eabi-gcc" --version
			fi
		'
	stage_and_write_provenance
}

install_dependencies() {
	local sudo_cmd=()
	[[ $(id -u) == 0 ]] || sudo_cmd=(sudo)
	case "$(uname -s)" in
	Darwin)
		brew install autoconf automake libtool texinfo ccache
		;;
	Linux)
		local -a extra=()
		case $host in
		x86_64-w64-mingw32) extra=(g++-mingw-w64-x86-64) ;;
		x86_64-unknown-freebsd | aarch64-unknown-freebsd) extra=(clang lld llvm) ;;
		esac
		${sudo_cmd[@]+"${sudo_cmd[@]}"} apt-get update -qq
		${sudo_cmd[@]+"${sudo_cmd[@]}"} env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
			cmake cmake-data git build-essential autoconf automake libtool \
			texinfo bison flex pkg-config python3 python3-pip curl bzip2 xz-utils \
			libarchive-tools ccache \
			${extra[@]+"${extra[@]}"}
		pip3 install --quiet cmake==3.31.6
		;;
	esac
}

# gcc, binutils, gdb and newlib are autotools: they honour no CMake variable,
# and a shim directory in PATH is the only way they pick ccache up.
enable_ccache() {
	local shims sudo_cmd=()
	[[ $(id -u) == 0 ]] || sudo_cmd=(sudo)
	if [[ $(uname -s) == Darwin ]]; then
		shims="$(brew --prefix ccache)/libexec"
	else
		[[ -x /usr/sbin/update-ccache-symlinks ]] &&
			${sudo_cmd[@]+"${sudo_cmd[@]}"} /usr/sbin/update-ccache-symlinks
		shims=/usr/lib/ccache
	fi
	[[ -d $shims ]] || {
		printf 'no ccache shim directory at %s; building without it\n' "$shims" >&2
		return 0
	}
	export PATH="$shims:$PATH"
	ccache --zero-stats >/dev/null 2>&1 || true
}

report_ccache_statistics() {
	command -v ccache >/dev/null 2>&1 && ccache --show-stats || true
}

if [[ $stage == 1 ]]; then
	# Dispatch is on stage, not host name: the lock may reuse a name here
	# (e.g. x86_64-linux-gnu) that also appears at stage 2.
	install_dependencies
	enable_ccache
	cmake -S "$repo_root" -B build \
		-DVITASDK_TARGET_ONLY=ON \
		-DVITASDK_PROFILE="$profile" \
		-DVITASDK_SOURCE_REVISION="$revision" \
		-DVITASDK_SOURCE_DATE_EPOCH="$source_date_epoch"
	cmake --build build --target sysroot --parallel "$(ci_nproc)"
	report_ccache_statistics
	cp build/vitasdk-sysroot-*.tar.bz2 "$out_dir/"
	ci_write_provenance "$out_dir" "$host" "$build_id" "$(basename build/vitasdk-sysroot-*.tar.bz2)"
	exit 0
fi

if [[ $host == *-linux-musl ]]; then
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

# After the case block: every branch of it has installed ccache by now, and
# the shims must precede the cross toolchains those branches put on PATH.
enable_ccache

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
