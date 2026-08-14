#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 5 ]]; then
	printf 'usage: %s <sdk-root> <output-directory> <host-architecture> <version> <source-revision>\n' \
		"$0" >&2
	exit 2
fi

sdk_root=$1
output_directory=$2
host_architecture=$3
package_version=$4
source_revision=$5
source_date_epoch=${SOURCE_DATE_EPOCH:-}
script_directory=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

# The package client owns itself. Everything here is the thing that installs
# packages, not something the compiler needs, and keeping it inside the core
# means a one-line fix to the client costs a toolchain rebuild.
#
# etc/pacman.conf belongs to neither: refresh writes it on every use to name
# the selected channel, so a package owning it would reset that selection on
# its next upgrade.
# Windows keeps its runtime inside share/vdpm, in an MSYS root of its own, so
# the partition follows the layout rather than a single list of names.
if [[ $3 == *-w64-mingw32 ]]; then
	client_paths=( bin/vdpm.exe share/vdpm )
else
	client_paths=(
		bin/vdpm
		bin/vdpm-channel
		bin/pacman
		bin/pacman-conf
		bin/include
		share/vdpm
	)
fi

[[ -d $sdk_root && $sdk_root == /* && $sdk_root != / ]] || {
	printf 'SDK root must be an absolute, non-root directory\n' >&2
	exit 1
}
[[ $host_architecture =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
	printf 'invalid host architecture: %s\n' "$host_architecture" >&2
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
[[ -n $source_date_epoch && $source_date_epoch =~ ^[0-9]+$ ]] || {
	printf 'SOURCE_DATE_EPOCH must be set to a non-negative integer\n' >&2
	exit 1
}

mkdir -p "$output_directory"
output_directory=$(cd "$output_directory" && pwd -P)
sdk_root=$(cd "$sdk_root" && pwd -P)

# The client carries its own version, and the core depends on at least it, so
# the two can move at their own pace afterwards.
client_version=$(awk -F= '$1 == "version" { print $2; exit }' \
	"$sdk_root/share/vdpm/release-info.txt")
[[ $client_version =~ ^[A-Za-z0-9][A-Za-z0-9.+]*$ ]] || {
	printf 'the SDK does not record a usable client version\n' >&2
	exit 1
}

package_release=1
full_version=$package_version-$package_release
client_full_version=$client_version-$package_release

temporary_directory=$(mktemp -d "$output_directory/.vitasdk-core.XXXXXXXX")
cleanup() {
	rm -rf -- "$temporary_directory"
}
trap cleanup EXIT

core_root="$temporary_directory/core"
client_root="$temporary_directory/client"
mkdir -p "$core_root" "$client_root"
cp -a "$sdk_root/." "$core_root/"
rm -f "$core_root/.PKGINFO" "$core_root/.BUILDINFO" "$core_root/.MTREE" \
	"$core_root/etc/pacman.conf"

for path in "${client_paths[@]}"; do
	[[ -e $core_root/$path ]] || {
		printf 'the SDK does not carry %s\n' "$path" >&2
		exit 1
	}
	mkdir -p "$client_root/$(dirname "$path")"
	mv "$core_root/$path" "$client_root/$path"
done

set_tree_mtime() {
	local root=$1 timestamp
	if touch -h -d "@$source_date_epoch" "$root/.PKGINFO" 2>/dev/null; then
		find "$root" -exec touch -h -d "@$source_date_epoch" {} +
	else
		timestamp=$(date -r "$source_date_epoch" -u '+%Y%m%d%H%M.%S')
		find "$root" -exec touch -h -t "$timestamp" {} +
	fi
}

list_package_files() {
	local excluded=${1:-} path
	if [[ -n $excluded ]]; then
		while IFS= read -r -d '' path; do
			printf '%s\0' "${path#./}"
		done < <(find . -mindepth 1 ! -name "$excluded" -print0)
	else
		while IFS= read -r -d '' path; do
			printf '%s\0' "${path#./}"
		done < <(find . -mindepth 1 -print0)
	fi
}

build_package() {
	local name=$1 version=$2 description=$3 depends=$4 root=$5
	local filename="$name-$version-$host_architecture.pkg.tar.xz"
	local path="$output_directory/$filename"
	local installed_size

	[[ ! -e $path ]] || {
		printf 'package already exists: %s\n' "$path" >&2
		exit 1
	}

	installed_size=$(du -sk "$root" | awk '{ print $1 * 1024 }')
	{
		printf 'pkgname = %s\n' "$name"
		printf 'pkgbase = %s\n' "$name"
		printf 'pkgver = %s\n' "$version"
		printf 'pkgdesc = %s\n' "$description"
		printf 'url = https://vitasdk.org/\n'
		printf 'builddate = %s\n' "$source_date_epoch"
		printf 'packager = VitaSDK autobuilds\n'
		printf 'size = %s\n' "$installed_size"
		printf 'arch = %s\n' "$host_architecture"
		printf 'license = custom\n'
		[[ -n $depends ]] && printf 'depend = %s\n' "$depends"
		printf 'xdata = pkgtype=pkg\n'
	} > "$root/.PKGINFO"

	cat > "$root/.BUILDINFO" <<EOF
format = 2
pkgname = $name
pkgbase = $name
pkgver = $version
pkgarch = $host_architecture
packager = VitaSDK autobuilds
builddate = $source_date_epoch
buildtool = vitasdk-buildscripts
buildtoolver = $source_revision
EOF

	set_tree_mtime "$root"
	(
		cd "$root"
		list_package_files .MTREE | LC_ALL=C sort -z |
			COPYFILE_DISABLE=1 LANG=C bsdtar -cnf - --format=mtree \
				--no-acls --no-fflags --no-mac-metadata --no-xattrs \
				--options='!all,use-set,type,uid,gid,mode,time,size,sha256,link' \
				--uid 0 --gid 0 --null -T - |
			gzip -c -f -n > .MTREE
	)
	set_tree_mtime "$root"

	(
		cd "$root"
		list_package_files | LC_ALL=C sort -z |
			COPYFILE_DISABLE=1 LANG=C bsdtar -cnf - \
				--no-acls --no-fflags --no-mac-metadata --no-xattrs \
				--uid 0 --gid 0 --uname root --gname root --null -T - |
			xz -c -z -9 > "$path"
	)

	"$script_directory/validate-core-package.sh" "$path"
	printf '%s\n' "$path"
}

# The client goes first because the core depends on it, and pacman resolves a
# transaction in that order too.
build_package vdpm "$client_full_version" \
	'VitaSDK package client' '' "$client_root"
build_package vitasdk-core "$full_version" \
	'VitaSDK compiler toolchain and host tools' "vdpm>=$client_full_version" \
	"$core_root"
