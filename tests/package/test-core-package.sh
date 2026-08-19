#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/vitasdk-core-package.XXXXXXXX")
sdk_root="$temporary_root/sdk"
pacman_image='archlinux@sha256:c1829f370be8434135f43fb3acaef1256780804ac3b2d2eec90dfb1232e1ffdf'

cleanup() {
	chmod -R u+rwX "$temporary_root" 2>/dev/null || true
	rm -rf -- "$temporary_root"
}
trap cleanup EXIT

mkdir -p "$sdk_root/bin/include" "$sdk_root/libexec/vdpm" "$sdk_root/arm-vita-eabi/lib" \
	"$sdk_root/share/vdpm/licenses" "$sdk_root/etc"
cat > "$sdk_root/bin/arm-vita-eabi-gcc" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
for client in vdpm vdpm-channel; do
	cat > "$sdk_root/bin/$client" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
done
for client in pacman pacman-conf; do
	cat > "$sdk_root/libexec/vdpm/$client" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
done
chmod +x "$sdk_root/bin/arm-vita-eabi-gcc" "$sdk_root/libexec/vdpm/pacman" \
	"$sdk_root/libexec/vdpm/pacman-conf" "$sdk_root/bin/vdpm" "$sdk_root/bin/vdpm-channel"
printf 'refresh\n' > "$sdk_root/bin/include/refresh-repositories.sh"
printf 'archive\n' > "$sdk_root/arm-vita-eabi/lib/libfixture.a"
printf 'source=fixture\nworld vita (float-abi=hard)\n' > "$sdk_root/version_info.txt"
printf 'CARCH="vita"\n' > "$sdk_root/bin/makepkg.conf"
printf 'notices\n' > "$sdk_root/share/vdpm/THIRD_PARTY_NOTICES.md"
printf 'vdpm license\n' > "$sdk_root/share/vdpm/licenses/vdpm-LGPL-2.1.txt"
printf 'pacman license\n' > "$sdk_root/share/vdpm/licenses/pacman-GPL-2.0.txt"
printf 'version=0.1.0\nhost=x86_64-linux-gnu\n' > "$sdk_root/share/vdpm/release-info.txt"
printf 'stale\n' > "$sdk_root/etc/pacman.conf"

for output in one two; do
	SOURCE_DATE_EPOCH=1700000000 \
		"$repository_root/scripts/create-core-package.sh" \
		"$sdk_root" "$temporary_root/$output" x86_64-linux-gnu \
		0.1 0123456789abcdef
done

core_name=vitasdk-core-0.1-1-x86_64-linux-gnu.pkg.tar.xz
client_name=vdpm-0.1.0-1-x86_64-linux-gnu.pkg.tar.xz

# A core release is two packages, and both have to be reproducible: the client
# moves on its own schedule, so a rebuild that changed its bytes would publish
# an upgrade nobody asked for.
for package in "$core_name" "$client_name"; do
	cmp "$temporary_root/one/$package" "$temporary_root/two/$package"
done

core_entries=$(bsdtar -tf "$temporary_root/one/$core_name")
client_entries=$(bsdtar -tf "$temporary_root/one/$client_name")

for path in bin/vdpm bin/vdpm-channel libexec/vdpm/pacman libexec/vdpm/pacman-conf \
		bin/include/refresh-repositories.sh share/vdpm/release-info.txt; do
	grep -qx "$path" <<< "$client_entries" || {
		printf 'the client package does not own %s\n' "$path" >&2
		exit 1
	}
	grep -qx "$path" <<< "$core_entries" && {
		printf 'the core package still owns %s\n' "$path" >&2
		exit 1
	}
done

# Refresh rewrites it on every use to name the selected channel, so a package
# owning it would put the selection back on its next upgrade.
for entries in "$core_entries" "$client_entries"; do
	grep -qx 'etc/pacman.conf' <<< "$entries" && {
		printf 'a package owns etc/pacman.conf\n' >&2
		exit 1
	}
done

bsdtar -xOf "$temporary_root/one/$core_name" .PKGINFO |
	grep -qx 'depend = vdpm>=0.1.0-1' || {
		printf 'the core does not depend on the client that installs it\n' >&2
		exit 1
	}

docker run --rm \
	--platform linux/amd64 \
	--mount "type=bind,source=$temporary_root/one,target=/packages,readonly" \
	"$pacman_image" \
	bash -euc '
		cat > /pacman.conf <<EOF
[options]
Architecture = x86_64-linux-gnu vita
SigLevel = Never
EOF
		install -d /sdk/var/lib/pacman /sdk/var/cache/pacman/pkg
		pac() { pacman --config /pacman.conf --root /sdk \
			--dbpath /sdk/var/lib/pacman --cachedir /sdk/var/cache/pacman/pkg \
			--logfile /sdk/var/log/pacman.log "$@"; }
		install_packages() { pac --noscriptlet --noconfirm --upgrade "$@"; }

		# The dependency is what keeps the client alive across a core upgrade,
		# so the core must refuse to install without it.
		if install_packages /packages/vitasdk-core-*.pkg.tar.xz 2>/dev/null; then
			echo "the core installed without its client" >&2
			exit 1
		fi

		install_packages /packages/vdpm-*.pkg.tar.xz /packages/vitasdk-core-*.pkg.tar.xz
		test -x /sdk/bin/arm-vita-eabi-gcc
		test -x /sdk/bin/vdpm
		test -f /sdk/share/vdpm/THIRD_PARTY_NOTICES.md
		grep -qx "source=fixture" /sdk/version_info.txt
		test ! -e /sdk/etc/pacman.conf

		pac --query --owns /sdk/bin/vdpm | grep -q "vdpm 0.1.0-1"
		pac --query --owns /sdk/bin/arm-vita-eabi-gcc | grep -q "vitasdk-core 0.1-1"
	'

# Windows partitions by layout, not by a list of names, and the layout carries
# a rule the other hosts do not have: the MSYS runtime lives in a root of its
# own under share/vdpm. An msys-2.0.dll in the SDK's own usr/bin would make the
# SDK an MSYS root, and pacman would then write every bin/ file a package
# installs into usr/bin instead.
windows_root="$temporary_root/windows-sdk"
mkdir -p "$windows_root/bin" "$windows_root/arm-vita-eabi/lib" \
	"$windows_root/share/vdpm/licenses" "$windows_root/share/vdpm/msys/usr/bin"
printf 'gcc\n' > "$windows_root/bin/arm-vita-eabi-gcc.exe"
printf 'vdpm\n' > "$windows_root/bin/vdpm.exe"
printf 'archive\n' > "$windows_root/arm-vita-eabi/lib/libfixture.a"
printf 'source=fixture\nworld vita (float-abi=hard)\n' > "$windows_root/version_info.txt"
printf 'CARCH="vita"\n' > "$windows_root/bin/makepkg.conf"
printf 'notices\n' > "$windows_root/share/vdpm/THIRD_PARTY_NOTICES.md"
printf 'refresh\n' > "$windows_root/share/vdpm/refresh-repositories.ps1"
printf 'vdpm license\n' > "$windows_root/share/vdpm/licenses/vdpm-LGPL-2.1.txt"
printf 'pacman license\n' > "$windows_root/share/vdpm/licenses/pacman-GPL-2.0.txt"
printf 'version=0.1.0\nhost=x86_64-w64-mingw32\n' > "$windows_root/share/vdpm/release-info.txt"
for runtime in pacman.exe vdpm-channel.exe msys-2.0.dll; do
	printf '%s\n' "$runtime" > "$windows_root/share/vdpm/msys/usr/bin/$runtime"
done

SOURCE_DATE_EPOCH=1700000000 \
	"$repository_root/scripts/create-core-package.sh" \
	"$windows_root" "$temporary_root/windows" x86_64-w64-mingw32 \
	0.1 0123456789abcdef

windows_core=$(bsdtar -tf "$temporary_root/windows/vitasdk-core-0.1-1-x86_64-w64-mingw32.pkg.tar.xz")
windows_client=$(bsdtar -tf "$temporary_root/windows/vdpm-0.1.0-1-x86_64-w64-mingw32.pkg.tar.xz")

for path in bin/vdpm.exe share/vdpm/refresh-repositories.ps1 \
		share/vdpm/msys/usr/bin/pacman.exe share/vdpm/msys/usr/bin/msys-2.0.dll; do
	grep -qx "$path" <<< "$windows_client" || {
		printf 'the Windows client package does not own %s\n' "$path" >&2
		exit 1
	}
	grep -qx "$path" <<< "$windows_core" && {
		printf 'the Windows core package still owns %s\n' "$path" >&2
		exit 1
	}
done

grep -qx 'bin/arm-vita-eabi-gcc.exe' <<< "$windows_core" || {
	printf 'the Windows core package lost the toolchain\n' >&2
	exit 1
}

for entries in "$windows_core" "$windows_client"; do
	grep -q '^usr/' <<< "$entries" && {
		printf 'a Windows package installs into the SDK own usr/, which makes it an MSYS root\n' >&2
		exit 1
	}
done

# Repackaging the same sources moves the core's release and nothing else.
# Publishing the split inside an existing release is exactly that, and the
# client must not be dragged along: the same client version arriving as -2 in
# one series and -1 in another is an upgrade in one direction and a downgrade
# in the other, for a package whose bytes did not change.
SOURCE_DATE_EPOCH=1700000000 \
	"$repository_root/scripts/create-core-package.sh" \
	"$sdk_root" "$temporary_root/second" x86_64-linux-gnu \
	0.1 0123456789abcdef 2

[[ -f $temporary_root/second/vitasdk-core-0.1-2-x86_64-linux-gnu.pkg.tar.xz ]] || {
	printf 'the core did not take the release it was given\n' >&2
	exit 1
}
[[ -f $temporary_root/second/vdpm-0.1.0-1-x86_64-linux-gnu.pkg.tar.xz ]] || {
	printf 'the client followed the core release instead of keeping its own\n' >&2
	exit 1
}
bsdtar -xOf "$temporary_root/second/vitasdk-core-0.1-2-x86_64-linux-gnu.pkg.tar.xz" .PKGINFO |
	grep -qx 'depend = vdpm>=0.1.0-1' || {
		printf 'the core asks for a client release that is not published\n' >&2
		exit 1
	}

printf 'VitaSDK core package contracts passed\n'
