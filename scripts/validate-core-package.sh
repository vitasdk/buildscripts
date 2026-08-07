#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
	printf 'usage: %s <vitasdk-core-*.pkg.tar.*>\n' "$0" >&2
	exit 2
fi

package=$1
require_package_client=${REQUIRE_PACKAGE_CLIENT:-1}

[[ -f $package ]] || {
	printf 'core package not found: %s\n' "$package" >&2
	exit 1
}

package_filename=${package##*/}
pkginfo=$(bsdtar -xOf "$package" .PKGINFO) || {
	printf 'cannot read .PKGINFO from %s\n' "$package_filename" >&2
	exit 1
}

pkgname=$(awk -F ' = ' '$1 == "pkgname" { print $2; exit }' <<< "$pkginfo")
pkgver=$(awk -F ' = ' '$1 == "pkgver" { print $2; exit }' <<< "$pkginfo")
architecture=$(awk -F ' = ' '$1 == "arch" { print $2; exit }' <<< "$pkginfo")

[[ $pkgname == vitasdk-core && -n $pkgver && -n $architecture ]] || {
	printf 'invalid core package identity\n' >&2
	exit 1
}
[[ $package_filename == "vitasdk-core-$pkgver-$architecture.pkg.tar."* ]] || {
	printf 'core package filename does not match its metadata: %s\n' \
		"$package_filename" >&2
	exit 1
}

archive_entries=$(bsdtar -tf "$package")
for metadata in .PKGINFO .BUILDINFO .MTREE; do
	grep -qx "$metadata" <<< "$archive_entries" || {
		printf '%s is missing from %s\n' "$metadata" "$package_filename" >&2
		exit 1
	}
done

if grep -E '(^/|(^|/)\.\.(/|$))' <<< "$archive_entries"; then
	printf 'core package contains an unsafe path\n' >&2
	exit 1
fi
bsdtar -xOf "$package" .MTREE | gzip -t

grep -Eq '^bin/arm-vita-eabi-gcc(\.exe)?$' <<< "$archive_entries" || {
	printf 'core package does not contain the Vita compiler driver\n' >&2
	exit 1
}
grep -qx 'version_info.txt' <<< "$archive_entries" || {
	printf 'core package does not contain provenance information\n' >&2
	exit 1
}
grep -qx 'etc/pacman.conf' <<< "$archive_entries" || {
	printf 'core package does not contain pacman.conf\n' >&2
	exit 1
}

if (( require_package_client )); then
	grep -Eq '^bin/pacman(\.exe)?$' <<< "$archive_entries" || {
		printf 'core package does not contain the package client\n' >&2
		exit 1
	}
fi

pacman_configuration=$(bsdtar -xOf "$package" etc/pacman.conf)
grep -Eq "^Architecture = ${architecture//./\.} vita$" \
	<<< "$pacman_configuration" || {
	printf 'pacman.conf does not select the core host and vita architectures\n' >&2
	exit 1
}
grep -qx 'SigLevel = Never' <<< "$pacman_configuration" || {
	printf 'pacman.conf does not declare the external trust model\n' >&2
	exit 1
}
grep -Fqx '# vdpm verifies signed channel metadata and the selected database hash before use.' \
	<<< "$pacman_configuration" || {
	printf 'pacman.conf does not document the external trust boundary\n' >&2
	exit 1
}
if grep -E '^\[[^]]+\]$' <<< "$pacman_configuration" |
	grep -vxq '\[options\]'; then
	printf 'core package must not embed a mutable repository URL\n' >&2
	exit 1
fi

printf 'validated core package %s for %s\n' "$pkgver" "$architecture"
