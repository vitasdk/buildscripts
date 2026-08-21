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

# A core release ships the toolchain and the client that installs it, as two
# packages, so both names are valid here and each has to own its own file name.
[[ ($pkgname == vitasdk-core || $pkgname == vdpm) && -n $pkgver && -n $architecture ]] || {
	printf 'invalid core package identity\n' >&2
	exit 1
}
[[ $package_filename == "$pkgname-$pkgver-$architecture.pkg.tar."* ]] || {
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

if [[ $pkgname == vitasdk-core ]]; then
	grep -Eq '^bin/arm-vita-eabi-gcc(\.exe)?$' <<< "$archive_entries" || {
		printf 'core package does not contain the Vita compiler driver\n' >&2
		exit 1
	}
	grep -qx 'version_info.txt' <<< "$archive_entries" || {
		printf 'core package does not contain provenance information\n' >&2
		exit 1
	}
else
	grep -Eq '^bin/vdpm(\.exe)?$' <<< "$archive_entries" || {
		printf 'client package does not contain the package client\n' >&2
		exit 1
	}
fi
# Nothing owns etc/pacman.conf: refresh writes it to name the selected
# channel, and a package owning it would put the selection back.
grep -qx 'etc/pacman.conf' <<< "$archive_entries" && {
	printf '%s owns etc/pacman.conf\n' "$pkgname" >&2
	exit 1
}

# An msys-2.0.dll under the SDK's own usr/bin makes the SDK an MSYS root, and
# an MSYS root turns /bin into an alias of /usr/bin: pacman would then write
# every bin/ file a package installs -- the whole toolchain front end -- into
# usr/bin instead. The runtime lives in a root of its own under share/vdpm, so
# nothing here may put anything in usr/. Repacking an older tree is how one
# would arrive back at it.
if [[ $architecture == *-w64-mingw32 ]] && grep -q '^usr/' <<< "$archive_entries"; then
	printf '%s installs into the SDK own usr/, which makes it an MSYS root\n' \
		"$pkgname" >&2
	exit 1
fi

if [[ $pkgname == vdpm ]]; then
	for compliance_file in share/vdpm/THIRD_PARTY_NOTICES.md \
		share/vdpm/licenses/vdpm-LGPL-2.1.txt \
		share/vdpm/licenses/pacman-GPL-2.0.txt; do
		grep -Fqx "$compliance_file" <<< "$archive_entries" || {
			printf 'client package does not contain %s\n' "$compliance_file" >&2
			exit 1
		}
	done
	if [[ $architecture == *-w64-mingw32 ]]; then
		for runtime_file in bin/vdpm.exe \
				share/vdpm/msys/usr/bin/pacman.exe \
				share/vdpm/msys/usr/bin/vdpm-channel.exe \
				share/vdpm/msys/usr/bin/msys-2.0.dll \
				share/vdpm/refresh-repositories.ps1; do
			grep -Fqx "$runtime_file" <<< "$archive_entries" || {
				printf 'Windows client package does not contain %s\n' "$runtime_file" >&2
				exit 1
			}
		done
	else
		for runtime_file in bin/vdpm libexec/vdpm/pacman bin/vdpm-channel; do
			grep -Fqx "$runtime_file" <<< "$archive_entries" || {
				printf 'client package does not contain %s\n' "$runtime_file" >&2
				exit 1
			}
		done
	fi
fi

# The contract that pacman.conf selects both architectures, declares the
# external trust model and embeds no repository URL now belongs to whoever
# writes it, which is refresh, and is asserted in the client's own tests.

printf 'validated core package %s for %s\n' "$pkgver" "$architecture"
