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
package_release=1
full_version=$package_version-$package_release
package_filename="vitasdk-core-$full_version-$host_architecture.pkg.tar.xz"
package_path="$output_directory/$package_filename"

[[ ! -e $package_path ]] || {
	printf 'core package already exists: %s\n' "$package_path" >&2
	exit 1
}

temporary_directory=$(mktemp -d "$output_directory/.vitasdk-core.XXXXXXXX")
package_root="$temporary_directory/root"
cleanup() {
	rm -rf -- "$temporary_directory"
}
trap cleanup EXIT

mkdir -p "$package_root"
cp -a "$sdk_root/." "$package_root/"
rm -f "$package_root/.PKGINFO" "$package_root/.BUILDINFO" "$package_root/.MTREE"
mkdir -p "$package_root/etc"

cat > "$package_root/etc/pacman.conf" <<EOF
[options]
Architecture = $host_architecture vita
# vdpm verifies signed channel metadata and the selected database hash before use.
SigLevel = Never
EOF

installed_size=$(du -sk "$package_root" | awk '{ print $1 * 1024 }')
cat > "$package_root/.PKGINFO" <<EOF
pkgname = vitasdk-core
pkgbase = vitasdk-core
pkgver = $full_version
pkgdesc = VitaSDK compiler toolchain and host tools
url = https://vitasdk.org/
builddate = $source_date_epoch
packager = VitaSDK autobuilds
size = $installed_size
arch = $host_architecture
license = custom
xdata = pkgtype=pkg
EOF

cat > "$package_root/.BUILDINFO" <<EOF
format = 2
pkgname = vitasdk-core
pkgbase = vitasdk-core
pkgver = $full_version
pkgarch = $host_architecture
packager = VitaSDK autobuilds
builddate = $source_date_epoch
buildtool = vitasdk-buildscripts
buildtoolver = $source_revision
EOF

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

set_tree_mtime "$package_root"
(
	cd "$package_root"
	list_package_files .MTREE | LC_ALL=C sort -z |
		COPYFILE_DISABLE=1 LANG=C bsdtar -cnf - --format=mtree \
			--no-acls --no-fflags --no-mac-metadata --no-xattrs \
			--options='!all,use-set,type,uid,gid,mode,time,size,sha256,link' \
			--uid 0 --gid 0 --null -T - |
		gzip -c -f -n > .MTREE
)
set_tree_mtime "$package_root"

(
	cd "$package_root"
	list_package_files | LC_ALL=C sort -z |
		COPYFILE_DISABLE=1 LANG=C bsdtar -cnf - \
			--no-acls --no-fflags --no-mac-metadata --no-xattrs \
			--uid 0 --gid 0 --uname root --gname root --null -T - |
		xz -c -z -9 > "$package_path"
)

"$script_directory/validate-core-package.sh" "$package_path"
printf '%s\n' "$package_path"
