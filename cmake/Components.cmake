include_guard(GLOBAL)

# Central source manifest for the VitaSDK superbuild. Keep archive names and
# hashes together so version updates cannot accidentally mix artifacts.
set(GCC_VERSION 15.2.0)
set(GCC_HASH SHA256=438fd996826b0c82485a29da03a72d71d6e3541a83ec702df4271f6fe025d24e)
set(GCC_URL https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz)

set(ZLIB_VERSION 1.3.1)
set(ZLIB_HASH SHA256=9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23)
set(ZLIB_URL https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.gz)

# Private dependencies for the package client. They are built as static
# archives and are not installed as part of the SDK.
set(XZ_VERSION 5.8.3)
set(XZ_HASH SHA256=fff1ffcf2b0da84d308a14de513a1aa23d4e9aa3464d17e64b9714bfdd0bbfb6)
set(XZ_URL https://github.com/tukaani-project/xz/releases/download/v${XZ_VERSION}/xz-${XZ_VERSION}.tar.xz)

set(LIBARCHIVE_VERSION 3.8.9)
set(LIBARCHIVE_HASH SHA256=888c934f9d95648ecb9163dc8e23ab80a476ecb81a8f1154704a227b5b676dde)
set(LIBARCHIVE_URL https://www.libarchive.org/downloads/libarchive-${LIBARCHIVE_VERSION}.tar.xz)

set(OPENSSL_VERSION 3.5.7)
set(OPENSSL_HASH SHA256=a8c0d28a529ca480f9f36cf5792e2cd21984552a3c8e4aa11a24aa31aeac98e8)
set(OPENSSL_URL https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz)

set(CURL_VERSION 8.21.0)
set(CURL_HASH SHA256=aa1b66a70eace83dc624508745646c08ae561de512ab403adffb93ac87fc72e6)
set(CURL_URL https://curl.se/download/curl-${CURL_VERSION}.tar.xz)

set(PACMAN_VERSION 7.1.0)
set(PACMAN_REPOSITORY https://gitlab.archlinux.org/pacman/pacman.git)
set(PACMAN_TAG v${PACMAN_VERSION})
set(PACMAN_COMMIT 5683f8477a0afcc6b331766175a83445b2dcfe89)

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

set(BINUTILS_VERSION 2.43)
set(BINUTILS_HASH SHA256=b53606f443ac8f01d1d5fc9c39497f2af322d99e14cea5c0b4b124d630379365)
set(BINUTILS_URL https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz)

set(GDB_VERSION 15.2)
set(GDB_HASH SHA256=83350ccd35b5b5a0cba6b334c41294ea968158c573940904f00b92f76345314d)
set(GDB_URL https://ftp.gnu.org/gnu/gdb/gdb-${GDB_VERSION}.tar.xz)

set(LIBZIP_REPOSITORY https://github.com/vitasdk/libzip)
set(NEWLIB_REPOSITORY https://github.com/vitasdk/newlib)
set(SAMPLES_REPOSITORY https://github.com/vitasdk/samples)
set(HEADERS_REPOSITORY https://github.com/vitasdk/vita-headers)
set(TOOLCHAIN_REPOSITORY https://github.com/vitasdk/vita-toolchain)
set(PTHREAD_REPOSITORY https://github.com/vitasdk/pthread-embedded)
set(VDPM_REPOSITORY https://github.com/vitasdk/vdpm.git)
set(VITA_MAKEPKG_REPOSITORY https://github.com/vitasdk/vita-makepkg.git)

set(LIBZIP_TAG master CACHE STRING "libzip branch, commit id or tag")
set(NEWLIB_TAG vita CACHE STRING "newlib branch, commit id or tag")
set(SAMPLES_TAG master CACHE STRING "samples branch, commit id or tag")
set(HEADERS_TAG master CACHE STRING "vita-headers branch, commit id or tag")
set(TOOLCHAIN_TAG master CACHE STRING "vita-toolchain branch, commit id or tag")
set(PTHREAD_TAG master CACHE STRING "pthread-embedded branch, commit id or tag")
set(VDPM_TAG master CACHE STRING "vdpm branch, commit id or tag")
set(VITA_MAKEPKG_TAG master CACHE STRING "vita-makepkg branch, commit id or tag")
