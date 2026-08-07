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

mkdir -p "$sdk_root/bin" "$sdk_root/arm-vita-eabi/lib"
cat > "$sdk_root/bin/arm-vita-eabi-gcc" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
cat > "$sdk_root/bin/pacman" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
chmod +x "$sdk_root/bin/arm-vita-eabi-gcc" "$sdk_root/bin/pacman"
printf 'archive\n' > "$sdk_root/arm-vita-eabi/lib/libfixture.a"
printf 'source=fixture\n' > "$sdk_root/version_info.txt"

for output in one two; do
	SOURCE_DATE_EPOCH=1700000000 \
		"$repository_root/scripts/create-core-package.sh" \
		"$sdk_root" "$temporary_root/$output" x86_64-linux-gnu \
		0.1 0123456789abcdef
done

package_name=vitasdk-core-0.1-1-x86_64-linux-gnu.pkg.tar.xz
cmp "$temporary_root/one/$package_name" "$temporary_root/two/$package_name"

docker run --rm \
	--platform linux/amd64 \
	--mount "type=bind,source=$temporary_root/one/$package_name,target=/package.pkg.tar.xz,readonly" \
	"$pacman_image" \
	bash -euc '
		cat > /pacman.conf <<EOF
[options]
Architecture = x86_64-linux-gnu vita
SigLevel = Never
EOF
		install -d /sdk/var/lib/pacman /sdk/var/cache/pacman/pkg
		pacman --config /pacman.conf \
			--root /sdk \
			--dbpath /sdk/var/lib/pacman \
			--cachedir /sdk/var/cache/pacman/pkg \
			--logfile /sdk/var/log/pacman.log \
			--noscriptlet --upgrade --noconfirm /package.pkg.tar.xz
		test -x /sdk/bin/arm-vita-eabi-gcc
		test -x /sdk/bin/pacman
		grep -qx "source=fixture" /sdk/version_info.txt
	'

printf 'VitaSDK core package contracts passed\n'
