cmake_minimum_required(VERSION 3.0.2)

project(vitasdk)

# Use the following gcc version
set(GCC_VERSION 6.2.0)
set(GCC_HASH SHA256=9944589fc722d3e66308c0ce5257788ebd7872982a718aa2516123940671b7c5)

# Branches to fetch the different project targets. Can be overriden from command line.
set(NEWLIB_TAG vita CACHE string "newlib branch name, commit id or tag")
set(SAMPLES_TAG master CACHE string "samples branch name, commit id or tag")
set(HEADERS_TAG master CACHE string "vita-headers branch name, commit id or tag")
set(TOOLCHAIN_TAG master CACHE string "vita-toolchain branch name, commit id or tag")
set(PTHREAD_TAG master CACHE string "pthread-embedded branch name, commit id or tag")

# Location to save the downloaded tarballs. Can be overriden from command line.
set(DOWNLOAD_DIR ${CMAKE_BINARY_DIR}/downloads CACHE PATH "Default download path for tarballs")

set(OFFLINE YES CACHE BOOL "Check repo updates")

# Installation directory. Can be overriden from command line.
if (CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
    set(CMAKE_INSTALL_PREFIX ${CMAKE_BINARY_DIR}/vitasdk CACHE PATH "Default install path" FORCE)
endif ()

################## END OF CONFIGURABLE OPTIONS ##################

find_package(Git REQUIRED)
list(APPEND CMAKE_MODULE_PATH "${PROJECT_SOURCE_DIR}/cmake")

# Toolchain arch target
set(TARGET_ARCH arm-vita-eabi)
# Build date
string(TIMESTAMP BUILD_DATE "%Y-%m-%d_%H-%M-%S")

include(Utils)
include(GetTriplet)
include(ExternalProject)

# Identify host and build systems
get_host_triplet(HOST_NATIVE)
get_build_triplet(BUILD_NATIVE)

message(STATUS "Host:   ${HOST_NATIVE}")
message(STATUS "Build:  ${BUILD_NATIVE}")
message(STATUS "Target: ${TARGET_ARCH}")

# Set a custom package version (visible with --version)
set(PKGVERSION "GNU Tools for ARM Embedded Processors")

# Load the compiler flags to pass them to the other projects
load_flags(COMPILER_FLAGS)

# Function to build the dependencies required for the vitasdk toolchain/headers
function(toolchain_deps TOOLCHAIN_DEPS_DIR TOOLCHAIN_INSTALL_DIR TOOLCHAIN_SUFFIX)
    set(extra_macro_args ${ARGN})

    # Check if the toolchain file has been passed as optional argument
    list(LENGTH extra_macro_args num_extra_args)
    if (${num_extra_args} GREATER 0)
        list(GET extra_macro_args 0 TOOLCHAIN_FILE)
    endif ()

    if (TOOLCHAIN_FILE)
        # Use the host triplet when crosscompiling
        set(TOOLCHAIN_HOST ${HOST_NATIVE})
        set(TOOLCHAIN_CMAKE_ARGS -DCMAKE_TOOLCHAIN_FILE=${TOOLCHAIN_FILE})
        # Workaround for libelf configure step (doesn't detect the compiler)
        set(CC_COMPILER "${HOST_NATIVE}-gcc")
    else ()
        # Use the same host triplet as the build env
        set(TOOLCHAIN_HOST ${BUILD_NATIVE})
        # Use the default compiler
        set(CC_COMPILER "gcc")
    endif ()

    set(SUFFIX "_${TOOLCHAIN_SUFFIX}")

    ExternalProject_Add(zlib${SUFFIX}
        URL http://zlib.net/zlib-1.2.8.tar.gz
        URL_HASH SHA256=36658cb768a54c1d4dec43c3116c27ed893e88b02ecfcb44f2166f9c0b7f2a0d
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=${TOOLCHAIN_DEPS_DIR}
        ${TOOLCHAIN_CMAKE_ARGS}
        )

    # Rename the zlib static file on windows so matches the other platforms
    if (TOOLCHAIN_FILE AND ${CMAKE_SYSTEM_NAME} STREQUAL "Windows")
        ExternalProject_Add_Step(zlib${SUFFIX}
            copy_lib
            DEPENDEES install
            COMMAND ${CMAKE_COMMAND} -E copy
            ${TOOLCHAIN_DEPS_DIR}/lib/libzlibstatic.a
            ${TOOLCHAIN_DEPS_DIR}/lib/libz.a
            COMMENT "Copying libzlibstatic to libz"
            )

        # Tell libzip to use zlib static library (only on windows)
        set(LIBZIP_CONFIGURE -DCMAKE_C_FLAGS=-DZIP_STATIC)
    endif ()

    # Different configurations for the unix/windows builds of the toolchain
    if (${CMAKE_SYSTEM_NAME} STREQUAL "Windows")
        list(APPEND TOOLCHAIN_CMAKE_ARGS -DZIP_STATIC=ON)
    else ()
        list(APPEND TOOLCHAIN_CMAKE_ARGS -DUSE_BUNDLED_ENDIAN_H=ON)
    endif ()

    ExternalProject_Add(libzip${SUFFIX}
        DEPENDS zlib${SUFFIX}
        URL https://nih.at/libzip/libzip-1.1.3.tar.gz
        URL_HASH SHA256=1faa5a524dd4a12c43b6344e618edce1bf8050dfdb9d0f73f3cc826929a002b0
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        PATCH_COMMAND patch -d <SOURCE_DIR> -p3 -t -N < ${PROJECT_SOURCE_DIR}/patches/libzip.patch
        CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=${TOOLCHAIN_DEPS_DIR}
        ${TOOLCHAIN_CMAKE_ARGS} ${LIBZIP_CONFIGURE}
        -DZLIB_INCLUDE_DIR=${TOOLCHAIN_DEPS_DIR}/include
        -DZLIB_LIBRARY=${TOOLCHAIN_DEPS_DIR}/lib/libz.a
        )

    ExternalProject_add(libelf${SUFFIX}
        URL http://www.mr511.de/software/libelf-0.8.13.tar.gz
        URL_HASH SHA256=591a9b4ec81c1f2042a97aa60564e0cb79d041c52faa7416acb38bc95bd2c76d
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        PATCH_COMMAND patch -d <SOURCE_DIR> -p3 -t -N < ${PROJECT_SOURCE_DIR}/patches/libelf.patch
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env CC=${CC_COMPILER} ${COMPILER_FLAGS}
        ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
        --build=${BUILD_NATIVE}
        --host=${TOOLCHAIN_HOST}
        --prefix=${TOOLCHAIN_DEPS_DIR}
        --libdir=${TOOLCHAIN_DEPS_DIR}/lib
        --disable-shared
        --disable-nls
        )

    ExternalProject_add(jansson${SUFFIX}
        URL http://www.digip.org/jansson/releases/jansson-2.9.tar.bz2
        URL_HASH SHA256=77094fc1e113da0e2e65479488a0719f859b8f5bde3a6a0da88a1c73a88b5698
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
        ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
        --build=${BUILD_NATIVE}
        --host=${TOOLCHAIN_HOST}
        --prefix=${TOOLCHAIN_DEPS_DIR}
        --libdir=${TOOLCHAIN_DEPS_DIR}/lib
        --disable-shared
        --enable-static
        )

    ExternalProject_add(gmp${SUFFIX}
        URL https://gmplib.org/download/gmp/gmp-6.1.1.tar.bz2
        URL_HASH SHA256=a8109865f2893f1373b0a8ed5ff7429de8db696fc451b1036bd7bdf95bbeffd6
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env CPPFLAGS=-fexceptions ${COMPILER_FLAGS}
        ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
        --build=${BUILD_NATIVE}
        --host=${TOOLCHAIN_HOST}
        --prefix=${TOOLCHAIN_DEPS_DIR}
        --libdir=${TOOLCHAIN_DEPS_DIR}/lib
        --enable-cxx
        --disable-shared
        BUILD_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
        ${PROJECT_SOURCE_DIR}/command_wrapper.sh $(MAKE)
        )

    ExternalProject_add(mpfr${SUFFIX}
        DEPENDS gmp${SUFFIX}
        URL http://ftp.gnu.org/gnu/mpfr/mpfr-3.1.5.tar.bz2
        URL_HASH SHA256=ca498c1c7a74dd37a576f353312d1e68d490978de4395fa28f1cbd46a364e658
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
        ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
        --build=${BUILD_NATIVE}
        --host=${TOOLCHAIN_HOST}
        --prefix=${TOOLCHAIN_DEPS_DIR}
        --libdir=${TOOLCHAIN_DEPS_DIR}/lib
        --with-gmp=${TOOLCHAIN_DEPS_DIR}
        --disable-shared
        )

    ExternalProject_add(mpc${SUFFIX}
        DEPENDS gmp${SUFFIX} mpfr${SUFFIX}
        URL http://www.multiprecision.org/mpc/download/mpc-1.0.3.tar.gz
        URL_HASH SHA256=617decc6ea09889fb08ede330917a00b16809b8db88c29c31bfbb49cbf88ecc3
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
        ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
        --build=${BUILD_NATIVE}
        --host=${TOOLCHAIN_HOST}
        --prefix=${TOOLCHAIN_DEPS_DIR}
        --libdir=${TOOLCHAIN_DEPS_DIR}/lib
        --with-gmp=${TOOLCHAIN_DEPS_DIR}
        --with-mpfr=${TOOLCHAIN_DEPS_DIR}
        --disable-shared
        --disable-nls
        )

    ExternalProject_add(isl${SUFFIX}
        DEPENDS gmp${SUFFIX}
        URL http://isl.gforge.inria.fr/isl-0.17.1.tar.bz2
        URL_HASH SHA256=d6307bf9a59514087abac3cbaab3d99393a0abb519354f7e7834a8c842310daa
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
        ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
        --build=${BUILD_NATIVE}
        --host=${TOOLCHAIN_HOST}
        --prefix=${TOOLCHAIN_DEPS_DIR}
        --libdir=${TOOLCHAIN_DEPS_DIR}/lib
        --with-gmp-prefix=${TOOLCHAIN_DEPS_DIR}
        --disable-shared
        )

    ExternalProject_add(cloog${SUFFIX}
        DEPENDS gmp${SUFFIX} isl${SUFFIX}
        URL http://www.bastoul.net/cloog/pages/download/cloog-0.18.4.tar.gz
        URL_HASH SHA256=325adf3710ce2229b7eeb9e84d3b539556d093ae860027185e7af8a8b00a750e
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
        ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
        --build=${BUILD_NATIVE}
        --host=${TOOLCHAIN_HOST}
        --prefix=${TOOLCHAIN_DEPS_DIR}
        --libdir=${TOOLCHAIN_DEPS_DIR}/lib
        --with-gmp-prefix=${TOOLCHAIN_DEPS_DIR}
        --with-isl-prefix=${TOOLCHAIN_DEPS_DIR}
        --disable-shared
        --disable-nls
        --with-bits=gmp
        --with-host-libstdcxx='-lstdc++'
        )

    ExternalProject_add(expat${SUFFIX}
        URL http://downloads.sourceforge.net/sourceforge/expat/expat-2.2.0.tar.bz2
        URL_HASH SHA256=d9e50ff2d19b3538bd2127902a89987474e1a4db8e43a66a4d1a712ab9a504ff
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
        ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
        --build=${BUILD_NATIVE}
        --host=${TOOLCHAIN_HOST}
        --prefix=${TOOLCHAIN_DEPS_DIR}
        --libdir=${TOOLCHAIN_DEPS_DIR}/lib
        --disable-shared
        )

    ExternalProject_Add(vita-toolchain${SUFFIX}
        DEPENDS jansson${SUFFIX} libelf${SUFFIX} zlib${SUFFIX} libzip${SUFFIX}
        GIT_REPOSITORY https://github.com/vitasdk/vita-toolchain
        GIT_TAG ${TOOLCHAIN_TAG}
        # Set prefix to "/" here to be able to install twice
        CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=/ ${TOOLCHAIN_CMAKE_ARGS}
        -DJansson_INCLUDE_DIR=${TOOLCHAIN_DEPS_DIR}/include
        -DJansson_LIBRARY=${TOOLCHAIN_DEPS_DIR}/lib/libjansson.a
        -Dlibelf_INCLUDE_DIR=${TOOLCHAIN_DEPS_DIR}/include
        -Dlibelf_LIBRARY=${TOOLCHAIN_DEPS_DIR}/lib/libelf.a
        -Dzlib_INCLUDE_DIR=${TOOLCHAIN_DEPS_DIR}/include
        -Dzlib_LIBRARY=${TOOLCHAIN_DEPS_DIR}/lib/libz.a
        -Dlibzip_INCLUDE_DIR=${TOOLCHAIN_DEPS_DIR}/include
        -Dlibzip_CONFIG_INCLUDE_DIR=${TOOLCHAIN_DEPS_DIR}/lib/libzip/include
        -Dlibzip_LIBRARY=${TOOLCHAIN_DEPS_DIR}/lib/libzip.a
        -DDEFAULT_JSON=../share/db.json
        BUILD_COMMAND $(MAKE)
        INSTALL_COMMAND $(MAKE) install DESTDIR=${TOOLCHAIN_INSTALL_DIR}
        # Save the commit id for tracking purposes
        COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/vita-toolchain-version.txt
        UPDATE_DISCONNECTED ${OFFLINE}
        )

    ExternalProject_Add(binutils${SUFFIX}
        URL https://ftp.gnu.org/gnu/binutils/binutils-2.27.tar.bz2
        URL_HASH SHA256=369737ce51587f92466041a97ab7d2358c6d9e1b6490b3940eb09fb0a9a6ac88
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        PATCH_COMMAND patch -d <SOURCE_DIR> -p3 -t -N < ${PROJECT_SOURCE_DIR}/patches/binutils.patch
        COMMAND patch -d <SOURCE_DIR> -p1 -t -N < ${PROJECT_SOURCE_DIR}/patches/binutils-2.27-fix-linker-segfault.patch
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
        ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
        --build=${BUILD_NATIVE}
        --host=${TOOLCHAIN_HOST}
        --target=${TARGET_ARCH}
        # Set prefix to "/" here to be able to install twice
        --prefix=/
        --with-sysroot=${TOOLCHAIN_INSTALL_DIR}
        --disable-nls
        --disable-werror
        --enable-interwork
        --enable-plugins
        "--with-pkgversion=${PKGVERSION}"
        BUILD_COMMAND $(MAKE)
        INSTALL_COMMAND $(MAKE) install DESTDIR=${TOOLCHAIN_INSTALL_DIR}
        )

    # Install binutils and vita-toolchain on CMAKE_INSTALL_PREFIX when not crosscompiling
    if (NOT TOOLCHAIN_FILE AND "${HOST_NATIVE}" STREQUAL "${BUILD_NATIVE}")
        ExternalProject_Add_Step(binutils${SUFFIX}
            install_sdk
            DEPENDEES install
            COMMAND $(MAKE) -C <BINARY_DIR> install DESTDIR=${CMAKE_INSTALL_PREFIX}
            COMMENT "Installing binutils to ${CMAKE_INSTALL_PREFIX}"
            )

        ExternalProject_Add_Step(vita-toolchain${SUFFIX}
            install_sdk
            DEPENDEES install
            COMMAND $(MAKE) -C <BINARY_DIR> install DESTDIR=${CMAKE_INSTALL_PREFIX}
            COMMENT "Installing vita-toolchain to ${CMAKE_INSTALL_PREFIX}"
            )
    endif ()
endfunction()

# Suffixes used for toolchain dependencies:
# * host: architecture where the toolchain is gonna be executed
# * build: architecture where the toolchain is being built
set(HOST_SUFFIX host)
set(BUILD_SUFFIX build)

# Only when using cross compilation
if (CMAKE_TOOLCHAIN_FILE)
    set(TARGET_SUFFIX ${HOST_SUFFIX})
    # Path of the host dependencies for gcc-final
    set(TOOLCHAIN_TARGET_DEPENDS_DIR "${CMAKE_BINARY_DIR}/deps_${TARGET_SUFFIX}")
    # Get the absolute path of the toolchain file, relative paths doesn't work with external projects
    get_filename_component(TOOLCHAIN_FILEPATH "${CMAKE_TOOLCHAIN_FILE}" ABSOLUTE)
    message(STATUS "Using toolchain file '${TOOLCHAIN_FILEPATH}'")
    # Build the host vita-toolchain, binutils and gcc-final depdndencies
    toolchain_deps("${TOOLCHAIN_TARGET_DEPENDS_DIR}" "${CMAKE_INSTALL_PREFIX}" "${HOST_SUFFIX}" "${TOOLCHAIN_FILEPATH}")
else ()
    set(TARGET_SUFFIX ${BUILD_SUFFIX})
    # Path of the build dependencies for gcc-final
    set(TOOLCHAIN_TARGET_DEPENDS_DIR "${CMAKE_BINARY_DIR}/deps_${TARGET_SUFFIX}")
endif ()

# Native toolchain install dir (used to build the real toolchain)
set(TOOLCHAIN_BUILD_INSTALL_DIR ${CMAKE_BINARY_DIR}/toolchain_${BUILD_SUFFIX})
# Native toolchain dependencies dir
SET(TOOLCHAIN_BUILD_DEPENDS_DIR ${CMAKE_BINARY_DIR}/deps_${BUILD_SUFFIX})
# Build the native vita-toolchain, gcc dependencies and binutils
toolchain_deps("${TOOLCHAIN_BUILD_DEPENDS_DIR}" "${TOOLCHAIN_BUILD_INSTALL_DIR}" "${BUILD_SUFFIX}")

# Command used on vita-header build step
set(VITA_LIBS_GEN_COMMAND "${TOOLCHAIN_BUILD_INSTALL_DIR}/bin/vita-libs-gen")
# Path where the temporary native binutils/gcc are being installed
set(BINUTILS_PREFIX "${TOOLCHAIN_BUILD_INSTALL_DIR}/bin/${TARGET_ARCH}")

# Tools for cross compilation (no need to override PATH with this)
list(APPEND TOOLCHAIN_TOOLS
    AR_FOR_TARGET=${BINUTILS_PREFIX}-ar
    LD_FOR_TARGET=${BINUTILS_PREFIX}-ld
    OBJDUMP_FOR_TARGET=${BINUTILS_PREFIX}-objdump
    NM_FOR_TARGET=${BINUTILS_PREFIX}-nm
    RANLIB_FOR_TARGET=${BINUTILS_PREFIX}-ranlib
    READELF_FOR_TARGET=${BINUTILS_PREFIX}-readelf
    STRIP_FOR_TARGET=${BINUTILS_PREFIX}-strip
    AS_FOR_TARGET=${BINUTILS_PREFIX}-as
    )

# Compilers for cross compilation (no need to override PATH with this)
list(APPEND COMPILER_TARGET_TOOLS
    CC_FOR_TARGET=${BINUTILS_PREFIX}-gcc
    GCC_FOR_TARGET=${BINUTILS_PREFIX}-gcc
    CXX_FOR_TARGET=${BINUTILS_PREFIX}-g++
    )

# Compilers used to build pthread-embedded (no need to override PATH with this)
list(APPEND PTHREAD_TOOLS
    CC=${BINUTILS_PREFIX}-gcc
    CXX=${BINUTILS_PREFIX}-g++
    AR=${BINUTILS_PREFIX}-ar
    )

if ("${CMAKE_CXX_COMPILER_ID}" MATCHES "Clang" AND ${CMAKE_SYSTEM_NAME} STREQUAL "Darwin")
    # GCC on OSX (Clang in diguise) needs more bracket nesting depth to compile gcc
    set(EXTRA_CFLAGS -fbracket-depth=512)
endif ()

# Common gcc configure options
set(COMMON_GCC_CONFIGURE_ARGS
    --with-python-dir=share/gcc-${TARGET_ARCH}
    --enable-languages=c,c++
    --disable-decimal-float
    --disable-libffi
    --disable-libgomp
    --disable-libmudflap
    --disable-libquadmath
    --disable-libssp
    --disable-libstdcxx-pch
    --disable-nls
    --disable-shared
    --disable-tls
    --with-gnu-as
    --with-gnu-ld
    --with-newlib
    --disable-multilib
    --with-arch=armv7-a
    --with-tune=cortex-a9
    --with-fpu=neon
    --with-float=hard
    --with-mode=thumb
    "--with-pkgversion=${PKGVERSION}"
    )

if ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "GNU")
    list(APPEND COMMON_GCC_CONFIGURE_ARGS "--with-host-libstdcxx=-static-libgcc -Wl,-Bstatic,-lstdc++,-Bdynamic -lm")
endif ()

# Build a basic gcc compiler, needed to compile newlib
ExternalProject_add(gcc-base
    DEPENDS gmp_${BUILD_SUFFIX} mpfr_${BUILD_SUFFIX} mpc_${BUILD_SUFFIX} isl_${BUILD_SUFFIX}
    DEPENDS cloog_${BUILD_SUFFIX} libelf_${BUILD_SUFFIX} expat_${BUILD_SUFFIX}
    URL http://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.bz2
    URL_HASH ${GCC_HASH}
    DOWNLOAD_DIR ${DOWNLOAD_DIR}
    PATCH_COMMAND patch -d <SOURCE_DIR> -p3 -t -N < ${PROJECT_SOURCE_DIR}/patches/gcc-6.patch
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env CFLAGS=${EXTRA_CFLAGS} CXXFLAGS=${EXTRA_CFLAGS} ${COMPILER_FLAGS}
    ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
    --build=${BUILD_NATIVE}
    # compile a native compiler so keep host == build
    --host=${BUILD_NATIVE}
    --target=${TARGET_ARCH}
    --prefix=${TOOLCHAIN_BUILD_INSTALL_DIR}
    --libdir=${TOOLCHAIN_BUILD_INSTALL_DIR}/lib
    --libexecdir=${TOOLCHAIN_BUILD_INSTALL_DIR}/lib
    --with-sysroot=${TOOLCHAIN_BUILD_INSTALL_DIR}/${TARGET_ARCH}
    --with-gmp=${TOOLCHAIN_BUILD_DEPENDS_DIR}
    --with-mpfr=${TOOLCHAIN_BUILD_DEPENDS_DIR}
    --with-mpc=${TOOLCHAIN_BUILD_DEPENDS_DIR}
    --with-isl=${TOOLCHAIN_BUILD_DEPENDS_DIR}
    --with-cloog=${TOOLCHAIN_BUILD_DEPENDS_DIR}
    --with-libelf=${TOOLCHAIN_BUILD_DEPENDS_DIR}
    ${COMMON_GCC_CONFIGURE_ARGS}
    --disable-threads
    --without-headers
    BUILD_COMMAND $(MAKE) all-gcc
    INSTALL_COMMAND $(MAKE) install-gcc
    )

ExternalProject_add(vita-headers
    DEPENDS binutils_${BUILD_SUFFIX} vita-toolchain_${BUILD_SUFFIX}
    GIT_REPOSITORY https://github.com/vitasdk/vita-headers
    GIT_TAG ${HEADERS_TAG}
    # TODO: vita-libs-gen should generate a proper makefile so this can be simplified
    CONFIGURE_COMMAND ${VITA_LIBS_GEN_COMMAND} <SOURCE_DIR>/db.json <BINARY_DIR>
    BUILD_COMMAND $(MAKE) ARCH=${BINUTILS_PREFIX}
    # Copy the generated .a files to the install directory
    INSTALL_COMMAND ${CMAKE_COMMAND} -DGLOB_PATTERN=<BINARY_DIR>/*a
    -DINSTALL_DIR=${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH}/lib
    -P ${CMAKE_SOURCE_DIR}/cmake/install_files.cmake
    # TODO: check if is actually needed for newlib/pthread-embedded targets
    COMMAND ${CMAKE_COMMAND} -E create_symlink . ${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH}/usr
    # Copy the include headers to the installation directory
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH}/include
    COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/include ${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH}/include
    # Install a copy of the headers in the toolchain directory (required for pthread-embedded target)
    COMMAND ${CMAKE_COMMAND} -E make_directory ${TOOLCHAIN_BUILD_INSTALL_DIR}/${TARGET_ARCH}/include
    COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/include ${TOOLCHAIN_BUILD_INSTALL_DIR}/${TARGET_ARCH}/include
    # Copy the json database to the installation directory
    COMMAND ${CMAKE_COMMAND} -DGLOB_PATTERN=<SOURCE_DIR>/db.json -DINSTALL_DIR=${CMAKE_INSTALL_PREFIX}/share
    -P ${CMAKE_SOURCE_DIR}/cmake/install_files.cmake
    # Save the commit id for tracking purposes
    COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/vita-headers-version.txt
    UPDATE_DISCONNECTED ${OFFLINE}
    )

ExternalProject_Add(newlib
    DEPENDS binutils_${TARGET_SUFFIX} gcc-base vita-headers
    GIT_REPOSITORY https://github.com/vitasdk/newlib
    GIT_TAG ${NEWLIB_TAG}
    # Pass the COMPILER_TARGET_TOOLS here so newlib picks up the fresh gcc-base compiler
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS} ${TOOLCHAIN_TOOLS} ${COMPILER_TARGET_TOOLS}
    "CFLAGS_FOR_TARGET=-g -O2 -ffunction-sections -fdata-sections"
    ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
    --build=${BUILD_NATIVE}
    --host=${HOST_NATIVE}
    --target=${TARGET_ARCH}
    # Use this prefix so the install target can be run twice with different paths
    --prefix=/
    --with-build-sysroot=${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH}
    --enable-newlib-io-long-long
    --enable-newlib-register-fini
    --disable-newlib-supplied-syscalls
    --disable-nls
    BUILD_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS} ${TOOLCHAIN_TOOLS}
    ${PROJECT_SOURCE_DIR}/command_wrapper.sh $(MAKE)
    INSTALL_COMMAND $(MAKE) install DESTDIR=${CMAKE_INSTALL_PREFIX}
    # Install a copy of newlib in the toolchain directory (required for pthread-embedded target)
    COMMAND $(MAKE) install DESTDIR=${TOOLCHAIN_BUILD_INSTALL_DIR}
    # Save the commit id for tracking purposes
    COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/newlib-version.txt
    UPDATE_DISCONNECTED ${OFFLINE}
    )

# Build a complete gcc compiler to be able to compile the full gcc for the host when crosscompiling.
# Using gcc-base doesn't work since is missing some headers.
if (CMAKE_TOOLCHAIN_FILE)
    ExternalProject_add(gcc-complete
        DEPENDS gmp_${BUILD_SUFFIX} mpfr_${BUILD_SUFFIX} mpc_${BUILD_SUFFIX} isl_${BUILD_SUFFIX}
        DEPENDS cloog_${BUILD_SUFFIX} libelf_${BUILD_SUFFIX} expat_${BUILD_SUFFIX} binutils_${BUILD_SUFFIX} newlib
        URL http://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.bz2
        URL_HASH ${GCC_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        PATCH_COMMAND patch -d <SOURCE_DIR> -p3 -t -N < ${PROJECT_SOURCE_DIR}/patches/gcc-6.patch
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env CFLAGS=${EXTRA_CFLAGS} CXXFLAGS=${EXTRA_CFLAGS}
        ${COMPILER_FLAGS} ${TOOLCHAIN_TOOLS}
        ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
        --build=${BUILD_NATIVE}
        # compile a native compiler so keep host == build
        --host=${BUILD_NATIVE}
        --target=${TARGET_ARCH}
        --prefix=${TOOLCHAIN_BUILD_INSTALL_DIR}
        --libdir=${TOOLCHAIN_BUILD_INSTALL_DIR}/lib
        --libexecdir=${TOOLCHAIN_BUILD_INSTALL_DIR}/lib
        --with-sysroot=${TOOLCHAIN_BUILD_INSTALL_DIR}/${TARGET_ARCH}
        --with-gmp=${TOOLCHAIN_BUILD_DEPENDS_DIR}
        --with-mpfr=${TOOLCHAIN_BUILD_DEPENDS_DIR}
        --with-mpc=${TOOLCHAIN_BUILD_DEPENDS_DIR}
        --with-isl=${TOOLCHAIN_BUILD_DEPENDS_DIR}
        --with-cloog=${TOOLCHAIN_BUILD_DEPENDS_DIR}
        --with-libelf=${TOOLCHAIN_BUILD_DEPENDS_DIR}
        ${COMMON_GCC_CONFIGURE_ARGS}
        --disable-threads
        --with-headers=yes
        BUILD_COMMAND ${CMAKE_COMMAND} -E env ${TOOLCHAIN_TOOLS}
        $(MAKE) INHIBIT_LIBC_CFLAGS="-DUSE_TM_CLONE_REGISTRY=0"
        INSTALL_COMMAND $(MAKE) install
        )
    # Add this target as dependency of the final gcc target
    set(GCC_DEPENDS gcc-complete)
else ()
    # Just use gcc-base as the dependency of the final gcc target
    set(GCC_DEPENDS gcc-base)
endif ()

ExternalProject_Add(pthread-embedded
    DEPENDS binutils_${TARGET_SUFFIX} gcc-base newlib vita-headers
    GIT_REPOSITORY https://github.com/vitasdk/pthread-embedded
    GIT_TAG ${PTHREAD_TAG}
    # TODO: this project should have a proper makefile to support out-of-source builds
    BUILD_IN_SOURCE 1
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
    ${PROJECT_SOURCE_DIR}/command_wrapper.sh $(MAKE)
    -C <SOURCE_DIR>/platform/vita ${PTHREAD_TOOLS} PREFIX=${CMAKE_INSTALL_PREFIX}
    INSTALL_COMMAND $(MAKE) -C <SOURCE_DIR>/platform/vita PREFIX=${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH} install
    # Save the commit id for tracking purposes
    COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/pthread-embedded-version.txt
    UPDATE_DISCONNECTED ${OFFLINE}
    )

ExternalProject_add(gcc-final
    DEPENDS gmp_${TARGET_SUFFIX} mpfr_${TARGET_SUFFIX} mpc_${TARGET_SUFFIX} isl_${TARGET_SUFFIX}
    DEPENDS cloog_${TARGET_SUFFIX} libelf_${TARGET_SUFFIX} expat_${TARGET_SUFFIX} binutils_${TARGET_SUFFIX}
    DEPENDS newlib ${GCC_DEPENDS} pthread-embedded
    URL http://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.bz2
    URL_HASH ${GCC_HASH}
    DOWNLOAD_DIR ${DOWNLOAD_DIR}
    PATCH_COMMAND patch -d <SOURCE_DIR> -p3 -t -N < ${PROJECT_SOURCE_DIR}/patches/gcc-6.patch
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env CFLAGS=${EXTRA_CFLAGS}
    CXXFLAGS=${EXTRA_CFLAGS} ${COMPILER_FLAGS} ${TOOLCHAIN_TOOLS} ${COMPILER_TARGET_TOOLS}
    ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
    --build=${BUILD_NATIVE}
    --host=${HOST_NATIVE}
    --target=${TARGET_ARCH}
    --prefix=${CMAKE_INSTALL_PREFIX}
    --libdir=${CMAKE_INSTALL_PREFIX}/lib
    --libexecdir=${CMAKE_INSTALL_PREFIX}/lib
    --with-sysroot=${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH}
    --with-gmp=${TOOLCHAIN_TARGET_DEPENDS_DIR}
    --with-mpfr=${TOOLCHAIN_TARGET_DEPENDS_DIR}
    --with-mpc=${TOOLCHAIN_TARGET_DEPENDS_DIR}
    --with-isl=${TOOLCHAIN_TARGET_DEPENDS_DIR}
    --with-cloog=${TOOLCHAIN_TARGET_DEPENDS_DIR}
    --with-libelf=${TOOLCHAIN_TARGET_DEPENDS_DIR}
    ${COMMON_GCC_CONFIGURE_ARGS}
    --with-headers=yes
    --enable-threads=posix
    BUILD_COMMAND ${CMAKE_COMMAND} -E env ${TOOLCHAIN_TOOLS} ${COMPILER_TARGET_TOOLS}
    $(MAKE) INHIBIT_LIBC_CFLAGS="-DUSE_TM_CLONE_REGISTRY=0"
    INSTALL_COMMAND $(MAKE) install
    # Remove empty include directory in the installation directory
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_INSTALL_PREFIX}/include
    )

ExternalProject_Add(samples
    GIT_REPOSITORY https://github.com/vitasdk/samples
    GIT_TAG ${SAMPLES_TAG}
    BUILD_IN_SOURCE 1
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ""
    INSTALL_COMMAND ${CMAKE_COMMAND}
    -DGLOB_PATTERN=<SOURCE_DIR> -DINSTALL_DIR=${CMAKE_INSTALL_PREFIX}/share/gcc-${TARGET_ARCH}
    -P ${CMAKE_SOURCE_DIR}/cmake/install_files.cmake
    # Save the commit id for tracking purposes
    COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/samples-version.txt
    UPDATE_DISCONNECTED ${OFFLINE}
    )

# Remove .la files from installation directory
add_custom_target(pretidy
    COMMAND ${CMAKE_COMMAND} -DGLOB_PATTERN=${CMAKE_INSTALL_PREFIX}/*.la
    -P ${CMAKE_SOURCE_DIR}/cmake/remove_files.cmake
    DEPENDS vita-headers gcc-final
    COMMENT "Removing .la files"
    )

# Strip toolchain binaries to reduce filesize
add_custom_target(strip_host_binaries
    COMMAND ${CMAKE_COMMAND} -DHOST_SYSTEM_NAME=${CMAKE_HOST_SYSTEM_NAME}
    -DBINDIR=${CMAKE_INSTALL_PREFIX}/bin
    -P ${CMAKE_SOURCE_DIR}/cmake/strip_host_binaries.cmake

    COMMAND ${CMAKE_COMMAND} -DHOST_SYSTEM_NAME=${CMAKE_HOST_SYSTEM_NAME}
    -DBINDIR=${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH}/bin
    -P ${CMAKE_SOURCE_DIR}/cmake/strip_host_binaries.cmake

    COMMAND ${CMAKE_COMMAND} -DHOST_SYSTEM_NAME=${CMAKE_HOST_SYSTEM_NAME}
    -DBINDIR=${CMAKE_INSTALL_PREFIX}/lib/gcc/${TARGET_ARCH}/${GCC_VERSION}
    -P ${CMAKE_SOURCE_DIR}/cmake/strip_host_binaries.cmake

    DEPENDS vita-toolchain_${TARGET_SUFFIX} binutils_${TARGET_SUFFIX} gcc-final
    COMMENT "Stripping host binaries"
    )

# Remove unnecessary sections from toolchain libraries
add_custom_target(strip_target_objects
    COMMAND ${CMAKE_COMMAND} -DOBJCOPY_COMMAND=${BINUTILS_PREFIX}-objcopy
    -DPATTERN_GLOB=${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH}/lib/*.[ao]
    -P ${CMAKE_SOURCE_DIR}/cmake/strip_target_objects.cmake

    COMMAND ${CMAKE_COMMAND} -DOBJCOPY_COMMAND=${BINUTILS_PREFIX}-objcopy
    -DPATTERN_GLOB=${CMAKE_INSTALL_PREFIX}/lib/gcc/${TARGET_ARCH}/${GCC_VERSION}/*.[ao]
    -P ${CMAKE_SOURCE_DIR}/cmake/strip_target_objects.cmake

    DEPENDS vita-headers gcc-final
    COMMENT "Stripping target objects"
    )

# Merge the commit ids of the collected projects into a single file
add_custom_target(version_info
    COMMAND ${CMAKE_COMMAND} -DINPUT_DIR=${CMAKE_BINARY_DIR} -DOUTPUT_DIR=${CMAKE_INSTALL_PREFIX}
    -P ${CMAKE_SOURCE_DIR}/cmake/create_version.cmake
    DEPENDS vita-headers vita-toolchain_${TARGET_SUFFIX} newlib pthread-embedded samples
    )

# Remove unnecessary docs from binutils/gcc installations
add_custom_target(cleanup
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_INSTALL_PREFIX}/share/man
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_INSTALL_PREFIX}/share/info
    DEPENDS binutils_${TARGET_SUFFIX} gcc-final
    COMMENT "Removing gcc/binutils docs"
    )

# Create a sdk tarball
add_custom_target(tarball ALL
    COMMAND ${CMAKE_COMMAND} -E tar "cfvj" "vitasdk-${HOST_NATIVE}-${BUILD_DATE}.tar.bz2" "${CMAKE_INSTALL_PREFIX}"
    DEPENDS vita-toolchain_${TARGET_SUFFIX} binutils_${TARGET_SUFFIX} vita-headers newlib pthread-embedded samples
    DEPENDS gcc-final pretidy cleanup strip_host_binaries strip_target_objects version_info
    COMMENT "Creating vitasdk-${host_os}-${BUILD_DATE}.tar.bz2"
    )
