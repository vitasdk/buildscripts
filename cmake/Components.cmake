include_guard(GLOBAL)

# Central source manifest for the VitaSDK superbuild. Keep archive names and
# hashes together so version updates cannot accidentally mix artifacts.
set(GCC_VERSION 15.2.0)
set(GCC_HASH SHA256=438fd996826b0c82485a29da03a72d71d6e3541a83ec702df4271f6fe025d24e)
# Everything below that GNU hosts is named three times, tried in order:
# mirrors.kernel.org, then ftpmirror.gnu.org, then ftp.gnu.org. URL_HASH
# decides whether what came back is the right bytes, so a mirror serving
# something else fails the way a corrupt download does.
#
# One host was one host too few. ftp.gnu.org refused connections for over two
# minutes at a time through 26 and 27 August, and each time it took a whole
# build with it -- six components come from there, and gdb is downloaded by
# every host.
#
# Two was also too few, for a different reason: ftpmirror.gnu.org is a
# redirector to whichever mirror is near, and the one it picked answered with
# an HTTP error. A named mirror goes first because it is the same host every
# time and can be seen to work; the redirector stays behind it as the thing
# that keeps working when that host does not.

set(GCC_URL
    https://mirrors.kernel.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz
    https://ftpmirror.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz
    https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz)

set(ZLIB_VERSION 1.3.1)
set(ZLIB_HASH SHA256=9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23)
set(ZLIB_URL https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.gz)

set(LIBELF_VERSION 0.8.13)
set(LIBELF_HASH SHA256=591a9b4ec81c1f2042a97aa60564e0cb79d041c52faa7416acb38bc95bd2c76d)
set(LIBELF_URL https://github.com/vitasdk/artifacts/releases/download/libelf-${LIBELF_VERSION}/libelf-${LIBELF_VERSION}.tar.gz)

set(LIBYAML_VERSION 0.2.2)
set(LIBYAML_HASH SHA256=4a9100ab61047fd9bd395bcef3ce5403365cafd55c1e0d0299cde14958e47be9)
set(LIBYAML_URL https://pyyaml.org/download/libyaml/yaml-${LIBYAML_VERSION}.tar.gz)

set(GMP_VERSION 6.3.0)
set(GMP_HASH SHA256=ac28211a7cfb609bae2e2c8d6058d66c8fe96434f740cf6fe2e47b000d1c20cb)
set(GMP_URL
    https://mirrors.kernel.org/gnu/gmp/gmp-${GMP_VERSION}.tar.bz2
    https://ftpmirror.gnu.org/gnu/gmp/gmp-${GMP_VERSION}.tar.bz2
    https://ftp.gnu.org/gnu/gmp/gmp-${GMP_VERSION}.tar.bz2)

set(MPFR_VERSION 4.2.2)
set(MPFR_HASH SHA256=9ad62c7dc910303cd384ff8f1f4767a655124980bb6d8650fe62c815a231bb7b)
set(MPFR_URL
    https://mirrors.kernel.org/gnu/mpfr/mpfr-${MPFR_VERSION}.tar.bz2
    https://ftpmirror.gnu.org/gnu/mpfr/mpfr-${MPFR_VERSION}.tar.bz2
    https://ftp.gnu.org/gnu/mpfr/mpfr-${MPFR_VERSION}.tar.bz2)

set(MPC_VERSION 1.3.1)
set(MPC_HASH SHA256=ab642492f5cf882b74aa0cb730cd410a81edcdbec895183ce930e706c1c759b8)
set(MPC_URL
    https://mirrors.kernel.org/gnu/mpc/mpc-${MPC_VERSION}.tar.gz
    https://ftpmirror.gnu.org/gnu/mpc/mpc-${MPC_VERSION}.tar.gz
    https://ftp.gnu.org/gnu/mpc/mpc-${MPC_VERSION}.tar.gz)

set(ISL_VERSION 0.24)
set(ISL_HASH SHA256=043105cc544f416b48736fff8caf077fb0663a717d06b1113f16e391ac99ebad)
set(ISL_REPOSITORY https://github.com/Meinersbur/isl)
set(ISL_TAG isl-${ISL_VERSION})

set(EXPAT_VERSION 2.3.0)
set(EXPAT_HASH SHA256=f122a20eada303f904d5e0513326c5b821248f2d4d2afbf5c6f1339e511c0586)
set(EXPAT_URL https://github.com/libexpat/libexpat/releases/download/R_2_3_0/expat-${EXPAT_VERSION}.tar.bz2)

set(BINUTILS_VERSION 2.46.1)
set(BINUTILS_HASH SHA256=e127a709cba24c76de8936cb7083dd768f28cd37eb010492e2f19b71eb1294e4)
set(BINUTILS_URL
    https://mirrors.kernel.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz
    https://ftpmirror.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz
    https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz)

set(GDB_VERSION 15.2)
set(GDB_HASH SHA256=83350ccd35b5b5a0cba6b334c41294ea968158c573940904f00b92f76345314d)
set(GDB_URL
    https://mirrors.kernel.org/gnu/gdb/gdb-${GDB_VERSION}.tar.xz
    https://ftpmirror.gnu.org/gnu/gdb/gdb-${GDB_VERSION}.tar.xz
    https://ftp.gnu.org/gnu/gdb/gdb-${GDB_VERSION}.tar.xz)

set(LIBZIP_VERSION 1.11.4)
set(LIBZIP_HASH SHA256=8a247f57d1e3e6f6d11413b12a6f28a9d388de110adc0ec608d893180ed7097b)
set(LIBZIP_URL https://libzip.org/download/libzip-${LIBZIP_VERSION}.tar.xz)

# Each VitaSDK component selects both its source and its revision from the
# command line. A local clone can be named here so that a change spanning two
# repositories can be built before either side is published.
set(NEWLIB_REPOSITORY https://github.com/vitasdk/newlib
    CACHE STRING "newlib repository URL or local path")
set(SAMPLES_REPOSITORY https://github.com/vitasdk/samples
    CACHE STRING "samples repository URL or local path")
set(HEADERS_REPOSITORY https://github.com/vitasdk/vita-headers
    CACHE STRING "vita-headers repository URL or local path")
set(TOOLCHAIN_REPOSITORY https://github.com/vitasdk/vita-toolchain
    CACHE STRING "vita-toolchain repository URL or local path")
set(PTHREAD_REPOSITORY https://github.com/vitasdk/pthread-embedded
    CACHE STRING "pthread-embedded repository URL or local path")
set(VDPM_REPOSITORY https://github.com/vitasdk/vdpm.git
    CACHE STRING "vdpm repository URL or local path")
set(VITA_MAKEPKG_REPOSITORY https://github.com/vitasdk/vita-makepkg.git
    CACHE STRING "vita-makepkg repository URL or local path")

set(NEWLIB_TAG 892f530fa7d696dbca74abfb8fccfec7d21d269d CACHE STRING "newlib branch, commit id or tag")
set(SAMPLES_TAG fe8fbef570f3280586c0c20157146e3faefb2181 CACHE STRING "samples branch, commit id or tag")
set(HEADERS_TAG 5e1e7d38d766e4c1634a77f6e5249caab8c8f9cb CACHE STRING "vita-headers branch, commit id or tag")
set(TOOLCHAIN_TAG eacff34d18e9872a78c0e520e1997ef71900ebb4 CACHE STRING "vita-toolchain branch, commit id or tag")
set(PTHREAD_TAG 11d2e5722d98c86f33c908fc47b2cf6e55205db5 CACHE STRING "pthread-embedded branch, commit id or tag")
set(VDPM_TAG v0.1.3 CACHE STRING "vdpm branch, commit id or tag")
set(VITA_MAKEPKG_TAG bbd1b18731cf8b6a69a18c9acdefd79a5b8c36eb CACHE STRING "vita-makepkg branch, commit id or tag")
