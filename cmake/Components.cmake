include_guard(GLOBAL)

# Central source manifest for the VitaSDK superbuild. Keep archive names and
# hashes together so version updates cannot accidentally mix artifacts.
set(GCC_VERSION 15.2.0)
set(GCC_HASH SHA256=438fd996826b0c82485a29da03a72d71d6e3541a83ec702df4271f6fe025d24e)
set(GCC_URL https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz)

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
set(GMP_URL https://ftp.gnu.org/gnu/gmp/gmp-${GMP_VERSION}.tar.bz2)

set(MPFR_VERSION 4.2.2)
set(MPFR_HASH SHA256=9ad62c7dc910303cd384ff8f1f4767a655124980bb6d8650fe62c815a231bb7b)
set(MPFR_URL https://ftp.gnu.org/gnu/mpfr/mpfr-${MPFR_VERSION}.tar.bz2)

set(MPC_VERSION 1.3.1)
set(MPC_HASH SHA256=ab642492f5cf882b74aa0cb730cd410a81edcdbec895183ce930e706c1c759b8)
set(MPC_URL https://ftp.gnu.org/gnu/mpc/mpc-${MPC_VERSION}.tar.gz)

set(ISL_VERSION 0.24)
set(ISL_HASH SHA256=043105cc544f416b48736fff8caf077fb0663a717d06b1113f16e391ac99ebad)
set(ISL_REPOSITORY https://github.com/Meinersbur/isl)
set(ISL_TAG isl-${ISL_VERSION})

set(EXPAT_VERSION 2.3.0)
set(EXPAT_HASH SHA256=f122a20eada303f904d5e0513326c5b821248f2d4d2afbf5c6f1339e511c0586)
set(EXPAT_URL https://github.com/libexpat/libexpat/releases/download/R_2_3_0/expat-${EXPAT_VERSION}.tar.bz2)

set(BINUTILS_VERSION 2.46.1)
set(BINUTILS_HASH SHA256=e127a709cba24c76de8936cb7083dd768f28cd37eb010492e2f19b71eb1294e4)
set(BINUTILS_URL https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz)

set(GDB_VERSION 15.2)
set(GDB_HASH SHA256=83350ccd35b5b5a0cba6b334c41294ea968158c573940904f00b92f76345314d)
set(GDB_URL https://ftp.gnu.org/gnu/gdb/gdb-${GDB_VERSION}.tar.xz)

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

set(NEWLIB_TAG 6cba98129f0a286949391de00519ef39762eff18 CACHE STRING "newlib branch, commit id or tag")
set(SAMPLES_TAG 99194cf828003dca6505d3762e10d14d152056f7 CACHE STRING "samples branch, commit id or tag")
set(HEADERS_TAG 17ac33bd2ff0ab71225824a7a99be6fc05d319e5 CACHE STRING "vita-headers branch, commit id or tag")
set(TOOLCHAIN_TAG c527abce028df33f5281e9ed4994c25fcef53c7d CACHE STRING "vita-toolchain branch, commit id or tag")
set(PTHREAD_TAG 63e1cd9152082d9ccb1b38d67a4caf975562fbeb CACHE STRING "pthread-embedded branch, commit id or tag")
set(VDPM_TAG 13165ca8fc49655fecaf8fd8895cd5aadf1f95cb CACHE STRING "vdpm branch, commit id or tag")
set(VITA_MAKEPKG_TAG 905038a8132405e0c70d21afff4612384c038168 CACHE STRING "vita-makepkg branch, commit id or tag")
