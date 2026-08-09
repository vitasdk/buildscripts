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
It contains the compiler, `vdpm`, Pacman, the signed-channel helper on Unix,
the MSYS runtime on Windows, configuration and provenance required by the
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
make audit-host-dependencies
```
