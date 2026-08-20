## VitaSDK. How to build.

```
apt-get install cmake git build-essential autoconf texinfo bison flex libtool
```

### Native compilation.

* Linux host -> Linux toolchain.
* OSX host -> OSX toolchain.

``` sh
mkdir build
cd build
cmake ..
make -j4
```

### Cross compilation.

* Linux host -> mingw32 toolchain

``` sh
mkdir build
cd build
cmake .. -DCMAKE_TOOLCHAIN_FILE=toolchain-x86_64-w64-mingw32.cmake
make -j4
```

### Cmake command-line options

You can pass then on the cmake phrase like this `cmake .. -DFOO=ON`.

If you want to fetch an specific revision of a part of the toolchain
then you can pass the branch/tag/id from the command line. The available
values are `NEWLIB_TAG`, `TOOLCHAIN_TAG`, `PTHREAD_TAG`, `HEADERS_TAG`,
`SAMPLES_TAG`, `VDPM_TAG` and `VITA_MAKEPKG_TAG`. For example:

``` sh
cmake /path/to/cmakelists -DNEWLIB_TAG=0254c2dc0c2686f69580030af3cacc795c94d616
```

This will configure the vitasdk to use that newlib commit instead of the `vita` branch.

The matching `NEWLIB_REPOSITORY`, `TOOLCHAIN_REPOSITORY`, `PTHREAD_REPOSITORY`,
`HEADERS_REPOSITORY`, `SAMPLES_REPOSITORY`, `VDPM_REPOSITORY` and
`VITA_MAKEPKG_REPOSITORY` values select where that revision comes from. A local
clone works, which is how a change spanning the superbuild and a component is
built before either side is published:

``` sh
cmake /path/to/cmakelists -DVDPM_REPOSITORY=/path/to/vdpm -DVDPM_TAG=next
```

### Package client and bootstrap archive

`vdpm` owns the package-client product. Buildscripts only incorporates that
component into the SDK. Enable the complete SDK-local client with:

``` sh
cmake /path/to/cmakelists -DBUILD_PACMAN_CLIENT=ON
cmake --build . --target bootstrap-archive
```

Production builds on every host consume the matching published vdpm bundle and
its immutable SHA-256. This keeps Linux, macOS and Windows on the same component
boundary and ensures the tested release is exactly what enters the SDK:

``` sh
cmake /path/to/cmakelists \
  -DBUILD_PACMAN_CLIENT=ON \
  -DVDPM_BUNDLE=/path/to/vdpm-<version>-<host-triplet>.tar.bz2 \
  -DVDPM_BUNDLE_SHA256=<64-lowercase-hex-digits>
cmake --build . --target bootstrap-archive
```

For development on Linux or macOS, omitting `VDPM_BUNDLE` explicitly falls
back to building `VDPM_REPOSITORY`/`VDPM_TAG` from source. Windows always
requires a release bundle because its Pacman runtime is produced under MSYS2.

The result is
`bootstraps/vitasdk-bootstrap-<host-triplet>.tar.bz2` plus its `.sha256`.
It contains the compiler, `vdpm`, Pacman, the signed-channel helper on every
host, the MSYS runtime on Windows, configuration and provenance required by the
standalone bootstrap scripts shipped by vdpm. The archive is reproducible for
the same finalized SDK tree and source-date epoch.

An existing legacy SDK whose state is still `packages.list` based is not an
in-place migration target. Install this bootstrap into a clean destination;
after that, the legacy shell frontend and the native `vdpm` frontend share the
same Pacman-owned package state.

If you need to change the download directory used for the tarballs then do the following,
for example:

``` sh
cmake /path/to/cmakelists -DDOWNLOAD_DIR=$HOME/vitasdk_tarballs
```

The remote repositories won't be checked for updates if you run `make` again.
If you don't want this behaviour then pass -DOFFLINE=NO to the cmake command line.
This is only available if your CMake installation is 3.2.0 or greater, else it will always
check for updates the next time you run make.

All Git-backed component sources are cloned with history depth 1. URL-based
source archives are already single immutable downloads and have no Git history.

### Static SDK contract

The default build keeps the Vita sysroot fully static and links every private
host dependency as a static archive. Host executables may still use the system
runtime supplied by the platform:

- Linux: the loader, libc and the small set of libraries shipped with the base
  C runtime (`libm`, `libpthread`, `libdl`, `librt`, `libutil`, `libresolv`).
- macOS: libraries and frameworks under `/usr/lib` and `/System/Library`.
- Windows: Windows system DLLs, plus the single `msys-2.0.dll` runtime shipped
  beside the MSYS Pacman executable under `usr/bin`. Native SDK tools remain
  independent of MSYS.

This is intentionally not a fully static host executable contract. In
particular, macOS does not provide a supported static system runtime. The
policy is a build invariant rather than an optional configuration mode.

To change the default installation path a path to CMAKE_INSTALL_PREFIX, for example:

``` sh
cmake /path/to/cmakelists -DCMAKE_INSTALL_PREFIX=$HOME/vitasdk
```

If you want to create a tarball of the sdk then run the following command:

``` sh
make tarball
```

The tarball target runs `finalize-sdk` first. Additional validation targets
are available after a complete build:

``` sh
make check-toolchain-contract
make check-static-policy
make check-sdk-partition
make audit-host-dependencies
```

## Staged builds

The build can run as a single native build (the historical behaviour, still
fully supported on every OS) or split into two stages. The split follows one
line: stage 1 compiles every artifact that is target code, and every other
host compiles only its own binaries.

* **Stage 1 — native Linux x86_64.** `cmake .. -DVITASDK_TARGET_ONLY=ON &&
  make sysroot`. Builds the target half and stops: the sysroot (newlib,
  pthread-embedded, vita-headers), the stubs and the target runtimes
  (libgcc, libstdc++, libgomp). No gdb, no package tools, no SDK
  validation — what it emits is not an SDK for any host, it is what every
  host imports. The compiler and binutils it had to build to get there stay
  behind in the build prefix.
* **Stage 2 — the hosts that are the machine building them** (Linux x86_64,
  arm64 Linux, macOS arm64). Unpack a stage-1 sysroot and point
  `VITASDK_STAGE1_DIR` at it:

  ```sh
  cmake .. -DVITASDK_STAGE1_DIR=/path/to/unpacked/sysroot
  make tarball
  ```

* **Stage 3 — the canadian crosses** (Windows, musl, FreeBSD, macOS
  x86_64). The same import plus a host toolchain file:

  ```sh
  cmake .. \
      -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/x86_64-w64-mingw32.cmake \
      -DVITASDK_STAGE1_DIR=/path/to/unpacked/sdk
  make tarball
  ```

  A cross build needs one thing beyond the sysroot: a working
  `arm-vita-eabi-gcc` **for the machine doing the building**, on PATH.
  `all-gcc` compiles no target code, but it runs the compiler exactly once
  — `-dumpspecs`, to write the specs file `GCC_PASSES` depends on — and a
  compiler built for another host cannot answer. Any stage-2 SDK for that
  machine's own host serves, which is why the CI matrix has a third level.

  Either way gcc is built through `all-gcc` alone: the compiler proper and
  nothing else. libgcc, the crt objects, the runtimes and the whole sysroot
  are imported, so no host but stage 1 ever compiles target code.

`cmake/SysrootManifest.cmake` holds the partition: what counts as target
code and what belongs to the host. The cut runs through files rather than
directories, because `<triple>/bin` is host binutils and
`lib/gcc/<triple>/<version>` mixes `cc1` with `libgcc.a`. `make
check-sdk-partition` covers it, and `finalize-sdk` rejects an SDK carrying a
binary built for another host.

Available host toolchain files under `cmake/toolchains/`:

| File | Host | Notes |
| --- | --- | --- |
| `x86_64-w64-mingw32.cmake` | Windows x86_64 | mingw-w64 |
| `i686-w64-mingw32.cmake` | Windows i686 | mingw-w64 |
| `x86_64-linux-musl.cmake` | Linux x86_64 (musl) | fully static; runs on Alpine and glibc distros |
| `aarch64-linux-musl.cmake` | Linux aarch64 (musl) | fully static |
| `aarch64-linux-gnu.cmake` | Linux aarch64 (glibc) | alternative to a native arm64 build |
| `x86_64-unknown-freebsd.cmake` | FreeBSD x86_64 | clang + base.txz sysroot, see `scripts/setup-freebsd-cross.sh` |
| `aarch64-unknown-freebsd.cmake` | FreeBSD aarch64 | clang + base.txz sysroot, see `scripts/setup-freebsd-cross.sh` |
| `x86_64-apple-darwin.cmake` | macOS x86_64 | requires osxcross; see file header |
| `aarch64-apple-darwin.cmake` | macOS arm64 | requires osxcross; see file header |

Building for your own OS (Linux, macOS, msys2) needs no stage-1 artifact and
behaves as it always has: `cmake .. && make tarball` produces a complete SDK
from source. What changed is that gcc is built once instead of twice — the
same tree yields the compiler and, after newlib and pthread-embedded are
built with it, the target libraries.

Cross building, on the other hand, now requires a stage-1 SDK. Target code
is compiled once and imported; a cross build that rebuilt it would be
compiling the same objects a second time on a machine that has no business
doing it. Configure without `VITASDK_STAGE1_DIR` and the build says so.
