# Pacman client spike

The rootless prototype is based on the upstream pacman 7.1.0 tag, peeled to
commit `5683f8477a0afcc6b331766175a83445b2dcfe89`. Clone it with:

```sh
git clone --depth 1 --branch v7.1.0 \
  https://gitlab.archlinux.org/pacman/pacman.git
```

Apply `patches/pacman/0001-allow-writable-non-root-installation-roots.patch`
with strip level 1 and zero fuzz. The patch preserves pacman's normal root
requirement for `/` and non-writable roots. For a writable alternate root it
lets the filesystem assign the unprivileged caller's UID/GID while retaining
the packaged permission bits.

The initial macOS arm64 diagnostic build used Meson 1.5.2 with:

```sh
meson setup build pacman \
  --buildtype=release \
  -Ddoc=disabled -Ddoxygen=disabled -Di18n=false \
  -Dgpgme=disabled -Dcurl=enabled -Dcrypto=openssl
meson compile -C build
```

Run the native contract as a non-root user, passing a patched pacman binary
and a `zlib-*-vita.pkg.tar.xz` produced by `vita-makepkg`:

```sh
tests/pacman/rootless-smoke.sh /path/to/pacman /path/to/zlib.pkg.tar.xz
```

The dynamic diagnostic build passes on macOS arm64. It is not a distributable
VitaSDK client: it links private Homebrew libraries. Upstream's
`-Dbuildstatic=true` selects static dependency variants but still builds and
links `libalpm` as a shared library; the macOS attempt also fails until static
transitive libarchive dependencies are supplied. Those are explicit gates for
the next spike.
