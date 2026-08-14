#!/usr/bin/env bash

# Turns a published SDK archive into a core the package client can install.
# The compiler, newlib and headers are kept exactly as they were built; the
# legacy shell client is replaced by a released vdpm bundle and the pinned
# vita-makepkg, and the result goes through the same core package and
# bootstrap archive scripts as a freshly built SDK.

set -euo pipefail

usage() {
	printf 'usage: %s --archive <sdk.tar.bz2> --host <triplet> --vdpm-bundle <bundle.tar.bz2>\n' "$0" >&2
	printf '           --vdpm-sha256 <hex> --vita-makepkg <checkout> --version <version>\n' >&2
	printf '           [--package-release <n>]\n' >&2
	printf '           --source-revision <hex> --output <directory>\n' >&2
	exit 2
}

archive=
host=
vdpm_bundle=
vdpm_sha256=
vita_makepkg=
package_version=
source_revision=
output_directory=

while (( $# )); do
	case $1 in
		--archive) archive=${2-}; shift 2 ;;
		--host) host=${2-}; shift 2 ;;
		--vdpm-bundle) vdpm_bundle=${2-}; shift 2 ;;
		--vdpm-sha256) vdpm_sha256=${2-}; shift 2 ;;
		--vita-makepkg) vita_makepkg=${2-}; shift 2 ;;
		--version) package_version=${2-}; shift 2 ;;
		--package-release) package_release=${2-}; shift 2 ;;
		--source-revision) source_revision=${2-}; shift 2 ;;
		--output) output_directory=${2-}; shift 2 ;;
		*) usage ;;
	esac
done

[[ -n $archive && -n $host && -n $vdpm_bundle && -n $vdpm_sha256 ]] || usage
[[ -n $vita_makepkg && -n $package_version && -n $source_revision ]] || usage
[[ -n $output_directory ]] || usage

script_directory=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

[[ -f $archive && ! -L $archive ]] || {
	printf 'SDK archive is not a regular file: %s\n' "$archive" >&2
	exit 1
}
[[ -f $vdpm_bundle && ! -L $vdpm_bundle ]] || {
	printf 'vdpm bundle is not a regular file: %s\n' "$vdpm_bundle" >&2
	exit 1
}
[[ -d $vita_makepkg ]] || {
	printf 'vita-makepkg checkout not found: %s\n' "$vita_makepkg" >&2
	exit 1
}
[[ $host =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
	printf 'invalid host triplet: %s\n' "$host" >&2
	exit 1
}
[[ $package_version =~ ^[A-Za-z0-9][A-Za-z0-9.+]*$ ]] || {
	printf 'invalid core package version: %s\n' "$package_version" >&2
	exit 1
}
[[ $source_revision =~ ^[0-9a-fA-F]{7,64}$ ]] || {
	printf 'source revision must be a hexadecimal Git object name\n' >&2
	exit 1
}
command -v cmake >/dev/null

archive=$(cd "$(dirname "$archive")" && pwd -P)/$(basename "$archive")
vdpm_bundle=$(cd "$(dirname "$vdpm_bundle")" && pwd -P)/$(basename "$vdpm_bundle")
vita_makepkg=$(cd "$vita_makepkg" && pwd -P)
mkdir -p "$output_directory"
output_directory=$(cd "$output_directory" && pwd -P)

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/vitasdk-repack.XXXXXXXX")
cleanup() { rm -rf -- "$temporary_directory"; }
trap cleanup EXIT

# A published archive carries the SDK under a single directory. Refuse anything
# that would write outside of it before extracting a byte.
while IFS= read -r entry; do
	case $entry in
		/*|../*|*/../*|*/..)
			printf 'SDK archive contains an unsafe path: %s\n' "$entry" >&2
			exit 1
			;;
	esac
done < <(tar -tjf "$archive")
tar -xjf "$archive" -C "$temporary_directory"
root_count=$(find "$temporary_directory" -mindepth 1 -maxdepth 1 -type d | wc -l)
(( root_count == 1 )) || {
	printf 'SDK archive does not hold a single root directory\n' >&2
	exit 1
}
sdk_root=$(find "$temporary_directory" -mindepth 1 -maxdepth 1 -type d -print -quit)

version_info="$sdk_root/version_info.txt"
[[ -f $version_info ]] || {
	printf 'SDK archive has no version_info.txt\n' >&2
	exit 1
}
[[ -e $sdk_root/bin/vdpm || -e $sdk_root/bin/vitasdk-update ]] || {
	printf 'SDK archive does not carry the legacy client; nothing to repack\n' >&2
	exit 1
}

source_date_epoch=${SOURCE_DATE_EPOCH:-}
if [[ -z $source_date_epoch ]]; then
	built_at=$(awk '/^Built at /{ sub(/^Built at /, ""); print; exit }' "$version_info")
	[[ -n $built_at ]] || {
		printf 'version_info.txt does not record a build date\n' >&2
		exit 1
	}
	source_date_epoch=$(date -u -d "$built_at" +%s 2>/dev/null ||
		date -u -j -f '%Y-%m-%d %H:%M:%S' "$built_at" +%s)
fi
[[ $source_date_epoch =~ ^[0-9]+$ ]] || {
	printf 'SOURCE_DATE_EPOCH must be a non-negative integer\n' >&2
	exit 1
}

# Everything the legacy client owned goes, so that a file it left behind can
# never shadow the new one: on Windows the old vdpm is a shell script and the
# new one is vdpm.exe, and both would sit in bin.
rm -rf -- "$sdk_root/bin/vdpm" "$sdk_root/bin/vdpm.exe" \
	"$sdk_root/bin/vitasdk-update" \
	"$sdk_root/bin/include/install-packages.sh" \
	"$sdk_root/bin/include/install-vitasdk.sh"

"$script_directory/install-vdpm-bundle.sh" \
	"$vdpm_bundle" "$vdpm_sha256" "$sdk_root" "$host"

# vita-makepkg ships inside the SDK, so the packages of this release would be
# built with whichever revision the original archive happened to carry.
rm -rf -- "$sdk_root/bin/libmakepkg"
cp -a "$vita_makepkg/libmakepkg" "$sdk_root/bin/libmakepkg"
cp -a "$vita_makepkg/vita-makepkg" "$sdk_root/bin/vita-makepkg"
cp -a "$vita_makepkg/makepkg.conf.sample" "$sdk_root/bin/makepkg.conf"

cmake -DOUTPUT="$sdk_root/etc/pacman.conf" -DHOST_ARCHITECTURE="$host" \
	-P "$script_directory/../cmake/WritePacmanConfig.cmake"

vdpm_version=$(awk -F= '$1 == "version" { print $2; exit }' \
	"$sdk_root/share/vdpm/release-info.txt")
[[ -n $vdpm_version ]] || {
	printf 'vdpm bundle does not record its version\n' >&2
	exit 1
}
if [[ -d $vita_makepkg/.git ]]; then
	vita_makepkg_revision=$(git -C "$vita_makepkg" rev-parse HEAD)
else
	vita_makepkg_revision=unknown
fi

if command -v sha256sum >/dev/null; then
	archive_digest=$(sha256sum "$archive")
else
	archive_digest=$(shasum -a 256 "$archive")
fi

# The component lines above this block still describe what produced the
# binaries. These say who repacked them and with what, and name the source
# archive by digest so the claim can be checked against what is published.
{
	printf 'repacked from     %s\n' "$(basename "$archive")"
	printf 'source sha256     %s\n' "${archive_digest%% *}"
	printf 'buildscripts      %s\n' "$source_revision"
	printf 'vdpm              %s\n' "$vdpm_version"
	printf 'vita-makepkg      %s\n' "$vita_makepkg_revision"
} >> "$version_info"

if touch -h -d "@$source_date_epoch" "$version_info" 2>/dev/null; then
	find "$sdk_root" -exec touch -h -d "@$source_date_epoch" {} +
else
	timestamp=$(date -r "$source_date_epoch" -u '+%Y%m%d%H%M.%S')
	find "$sdk_root" -exec touch -h -t "$timestamp" {} +
fi

SOURCE_DATE_EPOCH=$source_date_epoch "$script_directory/create-core-package.sh" \
	"$sdk_root" "$output_directory" "$host" "$package_version" "$source_revision" \
	"${package_release:-1}"

# The bootstrap archive is the whole SDK, so it is also the archive somebody
# downloads by hand. A build publishes a second, dated copy because its tree
# keeps moving while the two are cut; here both would come from the same
# normalised tree and be the same bytes under two names.
"$script_directory/create-bootstrap-archive.sh" \
	"$sdk_root" "$output_directory" "$host" "$source_date_epoch"
