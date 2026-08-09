# Pacman client spike

The rootless and MinGW prototypes are based on the upstream pacman 7.1.0 tag,
peeled to commit `5683f8477a0afcc6b331766175a83445b2dcfe89`. Clone it with:

```sh
git clone --depth 1 --branch v7.1.0 \
  https://gitlab.archlinux.org/pacman/pacman.git
```

Apply the relevant patches in `patches/pacman/` in numeric order with strip
level 1 and zero fuzz. The first patch preserves pacman's normal root
requirement for `/` and non-writable roots on Unix. Under MSYS it omits that
Unix-only privilege check, because the private runtime maps the SDK directory
itself to `/` and the process still has only the invoking Windows user's
filesystem rights. For an unprivileged caller it lets the filesystem assign
the UID/GID while retaining the packaged permission bits. The second patch
makes `-Dbuildstatic=true` embed the private libalpm archive in the command-line
clients instead of producing a shared libalpm.

The fourth patch keeps `setlocale()` active when gettext is disabled. Without
it, the reduced `-Di18n=false` client stays in the ASCII C application locale
and libarchive cannot read UTF-8 package paths, even though the MSYS runtime
uses UTF-8 internally for Windows filenames.

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
libraries. With the first two patches, `-Dbuildstatic=true` no longer creates a
`libalpm.dylib` target and its final link lines embed `libalpm_objlib.a`. The
hash-pinned static dependency build completes on macOS arm64, passes the host
audit, and the resulting client passes the rootless package contract. Native
Linux arm64 and x86_64 also complete with only libc and the system loader as
runtime dependencies. Windows uses the same pacman CLI through the MSYS ABI;
the minimal runtime contract is described below.

## Windows MSYS runtime

The selected version-one Windows design ships a pinned, patched `pacman.exe`
with exactly one adjacent non-system runtime, `msys-2.0.dll`. It does not ship
an MSYS2 shell, environment or tool collection. `vdpm.exe` starts pacman
directly and always supplies the SDK-local configuration, root, database,
cache and log paths.

Run the two-file contract on native Windows with PowerShell 7:

```powershell
./tests/pacman/msys-runtime-smoke.ps1
```

With no arguments, the test downloads hash-pinned official MSYS2 artifacts,
extracts only those two files, removes Git for Windows and installed MSYS2
directories from `PATH`, and performs install, query and remove operations on
a synthetic package.

The VitaSDK source-build regression is
`.github/workflows/msys-pacman-source.yml`. It installs the MSYS build tools,
runs:

```sh
tests/pacman/msys-pacman-build.sh /path/to/output
```

and passes the resulting `pacman.exe` and adjacent `msys-2.0.dll` to the same
PowerShell transaction test. The build clones tag 7.1.0, verifies commit
`5683f8477a0afcc6b331766175a83445b2dcfe89`, restores upstream symlinks, applies
the MSYS-relevant patches, embeds libalpm and its third-party libraries
statically, and rejects any PE import set other than `msys-2.0.dll`,
`CRYPT32.dll` and `KERNEL32.dll`.

That patched 7.1.0 pair passes install, query and remove on native Windows, so
the source build and two-file runtime shape are no longer open design work.
Release production still needs a pinned MSYS2 package snapshot (the CI
currently resolves its build dependencies from the current repository), exact
hashes and notices for the shipped pair, plus HTTPS repositories, UTF-8 and
long paths, case-insensitive collisions, locking and Windows rename/delete
tests.

## MinGW libalpm spike

The third patch ports only libalpm, not the pacman command-line client. On
Windows it disables the Unix user/process sandbox, syslog and scriptlets;
`CheckSpace` is also disabled until the mount-based implementation is replaced
with `GetDiskFreeSpaceExW`. Downloads continue through libcurl. POSIX regular
expressions come from libgnurx and a small adapter implements the flags-free
`fnmatch` subset used by libalpm.

The diagnostic build was reproduced in Fedora 42 with:

```sh
dnf install \
  meson ninja-build mingw64-gcc mingw64-libarchive mingw64-curl \
  mingw64-openssl mingw64-zlib mingw64-libgnurx-static

tests/pacman/mingw-libalpm-spike.sh \
  /path/to/patched-pacman /path/to/build-mingw-libalpm
```

The result is a MinGW static libalpm object archive and a PE64 smoke executable
that calls `alpm_initialize`, prints `alpm_version`, and releases the handle.
With Fedora's MinGW packages the smoke executable is 397 KiB and imports
libarchive, libcrypto, libcurl and libgnurx DLLs plus the Windows CRT. Building
those dependencies from the pinned static sources is separate follow-up work.

An `nm -u` audit of the archive found only `fnmatch` and `mkstemp` beyond the
expected MinGW CRT and third-party APIs. MinGW's runtime already supplies
`mkstemp`; the patch supplies `fnmatch`, while libgnurx supplies `regcomp`,
`regexec` and `regfree`. All 34 archive build steps complete without compiler
warnings and the smoke executable links without unresolved symbols.

The native MinGW binary has not passed a Windows transaction test. Wine 10.20
in the diagnostic container failed to finish its own prefix initialization,
so it did not provide a meaningful libalpm runtime result. This path is now a
preserved fallback rather than the version-one client: the MSYS pacman
two-file runtime has completed the native install/query/remove test without a
private VitaSDK POSIX compatibility layer.
