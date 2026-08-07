# Pacman client spike

The rootless prototype is based on the upstream pacman 7.1.0 tag, peeled to
commit `5683f8477a0afcc6b331766175a83445b2dcfe89`. Clone it with:

```sh
git clone --depth 1 --branch v7.1.0 \
  https://gitlab.archlinux.org/pacman/pacman.git
```

Apply the patches in `patches/pacman/` in numeric order with strip level 1 and
zero fuzz. The first patch preserves pacman's normal root requirement for `/`
and non-writable roots. For a writable alternate root it lets the filesystem
assign the unprivileged caller's UID/GID while retaining the packaged
permission bits. The second patch makes `-Dbuildstatic=true` embed the private
libalpm archive in the command-line clients instead of producing a shared
libalpm.

The initial macOS arm64 diagnostic build used Meson 1.5.2 with:

```sh
meson setup build pacman \
  --buildtype=release \
  -Ddoc=disabled -Ddoxygen=disabled -Di18n=false \
  -Dgpgme=disabled -Dcurl=enabled -Dcrypto=openssl
meson compile -C build
```

The reproducible static-client spike is opt-in and builds its private source
dependencies from the hashes in `cmake/Components.cmake`:

```sh
cmake -S . -B build-pacman -DBUILD_PACMAN_CLIENT=ON
cmake --build build-pacman --target pacman-client-spike --parallel
```

It currently supports native Linux and macOS builds. It builds private static
zlib, XZ, libarchive, OpenSSL and curl inputs, but installs only `pacman` and
`pacman-conf` below `build-pacman/pacman-client/bin`. Libarchive retains gzip
and XZ support needed by the repository and package formats. Curl retains only
HTTP/HTTPS, using Apple SecTrust on macOS. The target finishes by running the
same host dependency audit as the SDK.

Run the native contract as a non-root user, passing a patched pacman binary
and a `zlib-*-vita.pkg.tar.xz` produced by `vita-makepkg`:

```sh
tests/pacman/rootless-smoke.sh /path/to/pacman /path/to/zlib.pkg.tar.xz
```

The dynamic diagnostic build passes on macOS arm64 but links private Homebrew
libraries. With both patches, `-Dbuildstatic=true` no longer creates a
`libalpm.dylib` target and its final link lines embed `libalpm_objlib.a`. The
hash-pinned static dependency build completes on macOS arm64, passes the host
audit, and the resulting client passes the rootless package contract. Native
Linux arm64 also completes with only libc and the system loader as runtime
dependencies. Linux x86_64 and Windows remain explicit gates before selecting
the client.
