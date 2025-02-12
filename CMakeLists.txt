#
# Copyright(c) 2016 codestation
# Distributed under the MIT License (http://opensource.org/licenses/MIT)
#

cmake_minimum_required(VERSION 3.7.0)

project(vitasdk)

if(POLICY CMP0135)
    cmake_policy(SET CMP0135 NEW)
endif()

# Use the following gcc version
set(GCC_VERSION 13.2.0)
set(GCC_HASH SHA256=e275e76442a6067341a27f04c5c6b83d8613144004c0413528863dc6b5c743da)

set(ZLIB_VERSION 1.3)
set(ZLIB_HASH SHA256=8a9ba2898e1d0d774eca6ba5b4627a11e5588ba85c8851336eb38de4683050a7)

set(ZSTD_VERSION 1.5.5)
set(ZSTD_HASH SHA256=98e9c3d949d1b924e28e01eccb7deed865eefebf25c2f21c702e5cd5b63b85e1)

set(LIBELF_VERSION 0.8.13)
set(LIBELF_HASH SHA256=591a9b4ec81c1f2042a97aa60564e0cb79d041c52faa7416acb38bc95bd2c76d)

set(LIBYAML_VERSION 0.2.5)
set(LIBYAML_HASH SHA256=fa240dbf262be053f3898006d502d514936c818e422afdcf33921c63bed9bf2e)

set(GMP_VERSION 6.3.0)
set(GMP_HASH SHA256=a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898)

set(MPFR_VERSION 4.2.1)
set(MPFR_HASH SHA256=b9df93635b20e4089c29623b19420c4ac848a1b29df1cfd59f26cab0d2666aa0)

set(MPC_VERSION 1.3.1)
set(MPC_HASH SHA256=ab642492f5cf882b74aa0cb730cd410a81edcdbec895183ce930e706c1c759b8)

set(ISL_VERSION 0.21)

set(EXPAT_VERSION 2.5.0)
set(EXPAT_HASH SHA256=6f0e6e01f7b30025fa05c85fdad1e5d0ec7fd35d9f61b22f34998de11969ff67)
string(REPLACE "." "_" EXPAT_TAG_VERSION "${EXPAT_VERSION}")

set(BINUTILS_VERSION 2.41)
set(BINUTILS_HASH SHA256=ae9a5789e23459e59606e6714723f2d3ffc31c03174191ef0d015bdf06007450)

set(GDB_VERSION 13.2)
set(GDB_HASH SHA256=fd5bebb7be1833abdb6e023c2f498a354498281df9d05523d8915babeb893f0a)

# Branches to fetch the different project targets. Can be overriden from command line.
set(LIBZIP_TAG master CACHE STRING "libzip branch name, commit id or tag")
set(NEWLIB_TAG vita CACHE STRING "newlib branch name, commit id or tag")
set(SAMPLES_TAG master CACHE STRING "samples branch name, commit id or tag")
set(HEADERS_TAG master CACHE STRING "vita-headers branch name, commit id or tag")
set(TOOLCHAIN_TAG master CACHE STRING "vita-toolchain branch name, commit id or tag")
set(PTHREAD_TAG master CACHE STRING "pthread-embedded branch name, commit id or tag")
set(VDPM_TAG master CACHE STRING "vdpm branch name, commit id or tag")
set(VITA_MAKEPKG_TAG master CACHE STRING "vita-makepkg branch name, commit id or tag")

# Location to save the downloaded tarballs. Can be overriden from command line.
set(DOWNLOAD_DIR ${CMAKE_BINARY_DIR}/downloads CACHE PATH "Default download path for tarballs")

option(OFFLINE "Check repo updates" ON)

# Installation directory. Can be overriden from command line.
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
    set(CMAKE_INSTALL_PREFIX ${CMAKE_BINARY_DIR}/vitasdk CACHE PATH "Default install path" FORCE)
endif()

################## END OF CONFIGURABLE OPTIONS ##################

find_package(Git REQUIRED)
list(APPEND CMAKE_MODULE_PATH "${PROJECT_SOURCE_DIR}/cmake")

# Toolchain arch target
set(target_arch arm-vita-eabi)
# Build date
string(TIMESTAMP build_date "%Y-%m-%d_%H-%M-%S")

include(Utils)
include(GetTriplet)
include(ExternalProject)

# Identify host and build systems
get_host_triplet(host_native)
get_build_triplet(build_native)

message(STATUS "Host:   ${host_native}")
message(STATUS "Build:  ${build_native}")
message(STATUS "Target: ${target_arch}")

# Set a custom package version (visible with --version)
set(pkgversion "GNU Tools for ARM Embedded Processors")

# Load the compiler flags to pass them to the other projects
load_flags(compiler_flags)

set(wrapper_command ${PROJECT_SOURCE_DIR}/command_wrapper.sh)

# Function to build the dependencies required for the vitasdk toolchain/headers
function(toolchain_deps toolchain_deps_dir toolchain_install_dir toolchain_suffix)
    set(extra_macro_args ${ARGN})

    # Check if the toolchain file has been passed as optional argument
    list(LENGTH extra_macro_args num_extra_args)
    if(${num_extra_args} GREATER 0)
        list(GET extra_macro_args 0 toolchain_file)
    endif()

    if(toolchain_file)
        # Use the host triplet when crosscompiling
        set(toolchain_host ${host_native})
        set(toolchain_cmake_args -DCMAKE_TOOLCHAIN_FILE=${toolchain_file})
        # Workaround for libelf configure step (doesn't detect the toolchain)
        set(cc_compiler "${host_native}-gcc")
        set(ranlib "${host_native}-ranlib")
    else()
        # Use the same host triplet as the build env
        set(toolchain_host ${build_native})
        # Use the default toolchain
        set(cc_compiler "gcc")
        set(ranlib "ranlib")
    endif()

    set(suffix "_${toolchain_suffix}")

    ExternalProject_Add(zlib${suffix}
        URL https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.xz
        URL_HASH ${ZLIB_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        PATCH_COMMAND patch -d <SOURCE_DIR> -p1 -t -N < ${PROJECT_SOURCE_DIR}/patches/zlib.patch
        CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=${toolchain_deps_dir}
        ${toolchain_cmake_args}
        )

    # Rename the zlib static file on windows so matches the other platforms
    if(toolchain_file AND ${CMAKE_SYSTEM_NAME} STREQUAL "Windows")
        ExternalProject_Add_Step(zlib${suffix}
            copy_lib
            DEPENDEES install
            COMMAND ${CMAKE_COMMAND} -E copy
            ${toolchain_deps_dir}/lib/libzlibstatic.a
            ${toolchain_deps_dir}/lib/libz.a
            COMMENT "Copying libzlibstatic to libz"
            )

        # Tell libzip to use zlib static library (only on windows)
        set(libzip_configure -DCMAKE_C_FLAGS=-DZIP_STATIC)
    else()
        ExternalProject_Add_Step(zlib${suffix}
            delete_shared
            DEPENDEES install
            COMMAND ${CMAKE_COMMAND} -E remove
            ${toolchain_deps_dir}/lib/libz.so
            ${toolchain_deps_dir}/lib/libz.so.1
            ${toolchain_deps_dir}/lib/libz.dylib
            ${toolchain_deps_dir}/lib/libz.1.dylib
            ${toolchain_deps_dir}/lib/libz.1.2.13.dylib
            COMMENT "Delete shared libraries, if present"
            )
    endif()

    ExternalProject_Add(zstd${suffix}
        URL https://github.com/facebook/zstd/archive/refs/tags/v${ZSTD_VERSION}.tar.gz
        URL_HASH ${ZSTD_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        SOURCE_SUBDIR "build/cmake"
        CMAKE_ARGS ${toolchain_cmake_args}
        "-DCMAKE_INSTALL_PREFIX=${toolchain_deps_dir}"
        "-DCMAKE_BUILD_TYPE=Release"
        "-DZSTD_BUILD_CONTRIB=OFF"
        "-DZSTD_BUILD_PROGRAMS=OFF"
        "-DZSTD_BUILD_SHARED=OFF"
        "-DZSTD_BUILD_STATIC=ON"
        "-DZSTD_BUILD_TESTS=OFF"
        "-DZSTD_LEGACY_SUPPORT=OFF"
        "-DZSTD_MULTITHREAD_SUPPORT=OFF"
    )

    # Different configurations for the unix/windows builds of the toolchain
    if(${CMAKE_SYSTEM_NAME} STREQUAL "Windows")
        list(APPEND toolchain_cmake_args -DZIP_STATIC=ON)
    else()
        list(APPEND toolchain_cmake_args -DUSE_BUNDLED_ENDIAN_H=ON)
    endif()

    if(${CMAKE_SYSTEM_NAME} STREQUAL "Windows" AND (host_native STREQUAL build_native OR toolchain_file))
        list(APPEND toolchain_cmake_args -DBUILD_SHARED_LIBS=ON)
    else()
        list(APPEND toolchain_cmake_args -DBUILD_SHARED_LIBS=OFF)
    endif()

    ExternalProject_Add(libzip${suffix}
        DEPENDS zlib${suffix}
        GIT_REPOSITORY https://github.com/vitasdk/libzip
        GIT_TAG ${LIBZIP_TAG}
        GIT_SHALLOW 1
        UPDATE_DISCONNECTED ${OFFLINE}
        PATCH_COMMAND patch -d <SOURCE_DIR> -p3 -t -N < ${PROJECT_SOURCE_DIR}/patches/libzip.patch
        CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=${toolchain_deps_dir}
        ${toolchain_cmake_args} ${libzip_configure}
        -DZLIB_INCLUDE_DIR=${toolchain_deps_dir}/include
        -DZLIB_LIBRARY=${toolchain_deps_dir}/lib/libz.a
        )

    ExternalProject_add(libelf${suffix}
        URL https://github.com/vitasdk/artifacts/releases/download/libelf-${LIBELF_VERSION}/libelf-${LIBELF_VERSION}.tar.gz
        URL_HASH ${LIBELF_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        PATCH_COMMAND patch -d <SOURCE_DIR> -p3 -t -N < ${PROJECT_SOURCE_DIR}/patches/libelf/0001-sizeof-longlong.patch
        COMMAND patch -d <SOURCE_DIR> -p3 -t -N < ${PROJECT_SOURCE_DIR}/patches/libelf/0002-update-automake-configs.patch
        CONFIGURE_COMMAND autoreconf -fvi <SOURCE_DIR>
        COMMAND ${CMAKE_COMMAND} -E env CC=${cc_compiler} RANLIB=${ranlib} ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --prefix=${toolchain_deps_dir}
        --libdir=${toolchain_deps_dir}/lib
        --disable-shared
        --disable-nls
        )

    ExternalProject_add(libyaml${suffix}
        URL https://github.com/yaml/libyaml/archive/${LIBYAML_VERSION}.tar.gz
        URL_HASH ${LIBYAML_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        CONFIGURE_COMMAND autoreconf -fvi <SOURCE_DIR>
        COMMAND ${CMAKE_COMMAND} -E env ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --prefix=${toolchain_deps_dir}
        --libdir=${toolchain_deps_dir}/lib
        --disable-shared
        --enable-static
        "CFLAGS=-DYAML_DECLARE_STATIC"
        )

    ExternalProject_add(gmp${suffix}
        URL https://ftpmirror.gnu.org/gmp/gmp-${GMP_VERSION}.tar.xz
        URL_HASH ${GMP_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        CONFIGURE_COMMAND autoreconf -fvi <SOURCE_DIR>
        COMMAND ${CMAKE_COMMAND} -E env CPPFLAGS=-fexceptions ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --prefix=${toolchain_deps_dir}
        --libdir=${toolchain_deps_dir}/lib
        --enable-cxx
        --disable-shared
        )

    ExternalProject_add(mpfr${suffix}
        DEPENDS gmp${suffix}
        URL http://ftp.gnu.org/gnu/mpfr/mpfr-${MPFR_VERSION}.tar.bz2
        URL_HASH ${MPFR_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        PATCH_COMMAND autoreconf -fvi <SOURCE_DIR>
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --prefix=${toolchain_deps_dir}
        --libdir=${toolchain_deps_dir}/lib
        --with-gmp=${toolchain_deps_dir}
        --disable-shared
        )

    ExternalProject_add(mpc${suffix}
        DEPENDS gmp${suffix} mpfr${suffix}
        URL https://ftp.gnu.org/gnu/mpc/mpc-${MPC_VERSION}.tar.gz
        URL_HASH ${MPC_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --prefix=${toolchain_deps_dir}
        --libdir=${toolchain_deps_dir}/lib
        --with-gmp=${toolchain_deps_dir}
        --with-mpfr=${toolchain_deps_dir}
        --disable-shared
        --disable-nls
        )

    ExternalProject_add(isl${suffix}
        DEPENDS gmp${suffix}
        GIT_REPOSITORY https://github.com/Meinersbur/isl
        GIT_TAG isl-${ISL_VERSION}
        GIT_SHALLOW 1
        UPDATE_DISCONNECTED ${OFFLINE}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        CONFIGURE_COMMAND cd <SOURCE_DIR> && ./autogen.sh
        COMMAND ${CMAKE_COMMAND} -E env ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --prefix=${toolchain_deps_dir}
        --libdir=${toolchain_deps_dir}/lib
        --with-gmp-prefix=${toolchain_deps_dir}
        --disable-shared
        )

    ExternalProject_add(expat${suffix}
        URL https://github.com/libexpat/libexpat/releases/download/R_${EXPAT_TAG_VERSION}/expat-${EXPAT_VERSION}.tar.bz2
        URL_HASH ${EXPAT_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        PATCH_COMMAND autoreconf -fvi <SOURCE_DIR>
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --prefix=${toolchain_deps_dir}
        --libdir=${toolchain_deps_dir}/lib
        --disable-shared
        )

    ExternalProject_Add(vita-toolchain${suffix}
        DEPENDS libelf${suffix} zlib${suffix} libzip${suffix} libyaml${suffix}
        GIT_REPOSITORY https://github.com/vitasdk/vita-toolchain
        GIT_TAG ${TOOLCHAIN_TAG}
        GIT_SHALLOW 1
        # Set prefix to "/" here to be able to install twice
        CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=/ ${toolchain_cmake_args}
        -DTOOLCHAIN_DEPS_DIR=${toolchain_deps_dir}
        BUILD_COMMAND $(MAKE)
        INSTALL_COMMAND $(MAKE) install DESTDIR=${toolchain_install_dir}
        # Save the commit id for tracking purposes
        COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/vita-toolchain-version.txt
        UPDATE_DISCONNECTED ${OFFLINE}
        )

    ExternalProject_Add(binutils${suffix}
        DEPENDS zstd${suffix}
        URL https://ftpmirror.gnu.org/binutils/binutils-${BINUTILS_VERSION}.tar.xz
        URL_HASH ${BINUTILS_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        PATCH_COMMAND patch -d <SOURCE_DIR> -p3 -t -N < ${PROJECT_SOURCE_DIR}/patches/binutils/0001-vita.patch
        COMMAND patch -d <SOURCE_DIR> -p1 -t -N < ${PROJECT_SOURCE_DIR}/patches/binutils/0002-fix-broken-reloc.patch
        COMMAND patch -d <SOURCE_DIR> -p3 -t -N < ${PROJECT_SOURCE_DIR}/patches/binutils/0003-fix-elf-vaddr.patch
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --target=${target_arch}
        # Set prefix to "/" here to be able to install twice
        --prefix=/
        --with-sysroot=${toolchain_install_dir}
        --disable-nls
        --disable-werror
        --disable-separate-code
        --enable-interwork
        --enable-plugins
        "--with-pkgversion=${pkgversion}"
        # Binutils and gdb search for zstd using pkg-config
        --with-zstd
        "PKG_CONFIG_PATH=${toolchain_deps_dir}/lib/pkgconfig"
        BUILD_COMMAND $(MAKE)
        INSTALL_COMMAND $(MAKE) install DESTDIR=${toolchain_install_dir}
        )

    ExternalProject_Add(gdb${suffix}
        DEPENDS expat${suffix} gmp${suffix} mpfr${suffix} zlib${suffix} zstd${suffix}
        URL https://ftp.gnu.org/gnu/gdb/gdb-${GDB_VERSION}.tar.xz
        URL_HASH ${GDB_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        PATCH_COMMAND patch -d <SOURCE_DIR> -p1 -t -N < ${PROJECT_SOURCE_DIR}/patches/gdb.patch
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --target=${target_arch}
        # Set prefix to "/" here to be able to install twice
        --prefix=/
        --with-sysroot=${toolchain_install_dir}
        --with-libexpat-prefix=${toolchain_deps_dir}
        --with-libgmp-prefix=${toolchain_deps_dir}
        --with-libmpfr-prefix=${toolchain_deps_dir}
        --with-zstd
        # Avoid linking against system libs
        --disable-source-highlight
        --without-guile
        "PKG_CONFIG_PATH=${toolchain_deps_dir}/lib/pkgconfig"
        BUILD_COMMAND $(MAKE)
        INSTALL_COMMAND $(MAKE) install DESTDIR=${toolchain_install_dir}
        )

    # Install binutils, gdb and vita-toolchain on CMAKE_INSTALL_PREFIX when not crosscompiling
    if(NOT toolchain_file AND "${host_native}" STREQUAL "${build_native}")
        ExternalProject_Add_Step(binutils${suffix}
            install_sdk
            DEPENDEES build
            COMMAND $(MAKE) -C <BINARY_DIR> install DESTDIR=${CMAKE_INSTALL_PREFIX}
            # Remove binutils docs to reduce size
            COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_INSTALL_PREFIX}/share/man
            COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_INSTALL_PREFIX}/share/info
            COMMENT "Installing binutils to ${CMAKE_INSTALL_PREFIX}"
            )

        ExternalProject_Add_Step(gdb${suffix}
            install_sdk
            DEPENDEES build
            COMMAND $(MAKE) -C <BINARY_DIR> install DESTDIR=${CMAKE_INSTALL_PREFIX}
            COMMENT "Installing gdb to ${CMAKE_INSTALL_PREFIX}"
            )

        ExternalProject_Add_Step(vita-toolchain${suffix}
            install_sdk
            DEPENDEES build
            COMMAND $(MAKE) -C <BINARY_DIR> install DESTDIR=${CMAKE_INSTALL_PREFIX}
            COMMENT "Installing vita-toolchain to ${CMAKE_INSTALL_PREFIX}"
            )
    endif()
endfunction()

# Suffixes used for toolchain dependencies:
# * host: architecture where the toolchain is gonna be executed
# * build: architecture where the toolchain is being built
set(host_suffix host)
set(build_suffix build)

# Only when using cross compilation
if(CMAKE_TOOLCHAIN_FILE)
    set(target_suffix ${host_suffix})
    # Path of the host dependencies for gcc-final
    set(toolchain_target_depends_dir "${CMAKE_BINARY_DIR}/deps_${target_suffix}")
    # Get the absolute path of the toolchain file, relative paths doesn't work with external projects
    get_filename_component(toolchain_filepath "${CMAKE_TOOLCHAIN_FILE}" ABSOLUTE)
    message(STATUS "Using toolchain file '${toolchain_filepath}'")
    # Build the host vita-toolchain, binutils and gcc-final depdndencies
    toolchain_deps("${toolchain_target_depends_dir}" "${CMAKE_INSTALL_PREFIX}" "${host_suffix}" "${toolchain_filepath}")
else()
    set(target_suffix ${build_suffix})
    # Path of the build dependencies for gcc-final
    set(toolchain_target_depends_dir "${CMAKE_BINARY_DIR}/deps_${target_suffix}")
endif()

# Native toolchain install dir (used to build the real toolchain)
set(toolchain_build_install_dir ${CMAKE_BINARY_DIR}/toolchain_${build_suffix})
# Native toolchain dependencies dir
set(toolchain_build_depends_dir ${CMAKE_BINARY_DIR}/deps_${build_suffix})
# Build the native vita-toolchain, gcc dependencies and binutils
toolchain_deps("${toolchain_build_depends_dir}" "${toolchain_build_install_dir}" "${build_suffix}")

# Command used on vita-header build step
set(vita_libs_gen_command "${toolchain_build_install_dir}/bin/vita-libs-gen")
# Path where the temporary native binutils/gcc are being installed
set(binutils_prefix "${toolchain_build_install_dir}/bin/${target_arch}")

# Tools for cross compilation (no need to override PATH with this)
list(APPEND toolchain_tools
    AR_FOR_TARGET=${binutils_prefix}-ar
    LD_FOR_TARGET=${binutils_prefix}-ld
    OBJDUMP_FOR_TARGET=${binutils_prefix}-objdump
    NM_FOR_TARGET=${binutils_prefix}-nm
    RANLIB_FOR_TARGET=${binutils_prefix}-ranlib
    READELF_FOR_TARGET=${binutils_prefix}-readelf
    STRIP_FOR_TARGET=${binutils_prefix}-strip
    AS_FOR_TARGET=${binutils_prefix}-as
    )

# Compilers for cross compilation (no need to override PATH with this)
list(APPEND compiler_target_tools
    CC_FOR_TARGET=${binutils_prefix}-gcc
    GCC_FOR_TARGET=${binutils_prefix}-gcc
    CXX_FOR_TARGET=${binutils_prefix}-g++
    )

# Compilers used to build pthread-embedded (no need to override PATH with this)
list(APPEND pthread_tools
    CC=${binutils_prefix}-gcc
    CXX=${binutils_prefix}-g++
    AR=${binutils_prefix}-ar
    )

if("${CMAKE_CXX_COMPILER_ID}" MATCHES "Clang" AND ${CMAKE_SYSTEM_NAME} STREQUAL "Darwin")
    # GCC on OSX (Clang in diguise) needs more bracket nesting depth to compile gcc
    set(GCC_CFLAGS "${GCC_CFLAGS} -fbracket-depth=512")
endif()

# Common gcc configure options
set(common_gcc_configure_args
    --with-python-dir=share/gcc-${target_arch}
    --enable-languages=c,c++
    --disable-decimal-float
    --disable-libffi
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
    "--with-pkgversion=${pkgversion}"
    )

if("${CMAKE_CXX_COMPILER_ID}" STREQUAL "GNU")
    list(APPEND common_gcc_configure_args "--with-host-libstdcxx=-static-libgcc -Wl,-Bstatic,-lstdc++,-Bdynamic -lm")
endif()

# Build a basic gcc compiler, needed to compile newlib
ExternalProject_add(gcc-base
    DEPENDS gmp_${build_suffix} mpfr_${build_suffix} mpc_${build_suffix} isl_${build_suffix} libelf_${build_suffix} zstd_${build_suffix}
    URL https://ftpmirror.gnu.org/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz
    URL_HASH ${GCC_HASH}
    DOWNLOAD_DIR ${DOWNLOAD_DIR}
    PATCH_COMMAND patch -d <SOURCE_DIR> -p1 -t -N < ${PROJECT_SOURCE_DIR}/patches/gcc/0001-gcc-13-vita.patch
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${compiler_flag} ${wrapper_command} <SOURCE_DIR>/configure
    --build=${build_native}
    # compile a native compiler so keep host == build
    --host=${build_native}
    --target=${target_arch}
    --prefix=${toolchain_build_install_dir}
    --libdir=${toolchain_build_install_dir}/lib
    --libexecdir=${toolchain_build_install_dir}/lib
    --with-sysroot=${toolchain_build_install_dir}/${target_arch}
    --with-gmp=${toolchain_build_depends_dir}
    --with-mpfr=${toolchain_build_depends_dir}
    --with-mpc=${toolchain_build_depends_dir}
    --with-isl=${toolchain_build_depends_dir}
    --with-libelf=${toolchain_build_depends_dir}
    --with-zstd=${toolchain_build_depends_dir}
    ${common_gcc_configure_args}
    --disable-threads
    --without-headers
    --disable-libgomp
    "CFLAGS=${GCC_CFLAGS}"
    "CXXFLAGS=${GCC_CFLAGS}"
    BUILD_COMMAND $(MAKE) all-gcc
    INSTALL_COMMAND $(MAKE) install-gcc
    )

ExternalProject_add(vita-headers
    DEPENDS binutils_${build_suffix} vita-toolchain_${build_suffix}
    GIT_REPOSITORY https://github.com/vitasdk/vita-headers
    GIT_TAG ${HEADERS_TAG}
    GIT_SHALLOW 1
    # CONFIGURE_COMMAND ""
    # BUILD_COMMAND VITA_LIBS_GEN=${vita_libs_gen_command}
    #     ARCH=${binutils_prefix}
    #     BYPASS_INSTALL=1
    #     python <SOURCE_DIR>/build.py <BINARY_DIR>
    CONFIGURE_COMMAND ${vita_libs_gen_command}-2 -yml=<SOURCE_DIR>/db -output=<BINARY_DIR>
    BUILD_COMMAND ARCH=${binutils_prefix}
        make
    # Copy the generated .a files to the install directory
    # INSTALL_COMMAND ${CMAKE_COMMAND} -DGLOB_PATTERN=<BINARY_DIR>/*/*/*a
    INSTALL_COMMAND ${CMAKE_COMMAND} -DGLOB_PATTERN=<BINARY_DIR>/*.a
    -DINSTALL_DIR=${CMAKE_INSTALL_PREFIX}/${target_arch}/lib
    -P ${CMAKE_SOURCE_DIR}/cmake/install_files.cmake
    # Copy the include headers to the installation directory
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_INSTALL_PREFIX}/${target_arch}/include
    COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/include ${CMAKE_INSTALL_PREFIX}/${target_arch}/include
    # Copy the vita.header_warn.cmake to the installation directory
    COMMAND ${CMAKE_COMMAND} -E copy <SOURCE_DIR>/vita.header_warn.cmake ${CMAKE_INSTALL_PREFIX}/${target_arch}/vita.header_warn.cmake
    # Copy the generated .a files to the toolchain directory (required for libgomp target)
    COMMAND ${CMAKE_COMMAND} -E make_directory ${toolchain_build_install_dir}/${target_arch}/lib
    COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_INSTALL_PREFIX}/${target_arch}/lib ${toolchain_build_install_dir}/${target_arch}/lib
    # Install a copy of the headers in the toolchain directory (required for pthread-embedded target)
    COMMAND ${CMAKE_COMMAND} -E make_directory ${toolchain_build_install_dir}/${target_arch}/include
    COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/include ${toolchain_build_install_dir}/${target_arch}/include
    # Copy the yml database to the installation directory
    COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/db ${CMAKE_INSTALL_PREFIX}/share/vita-headers/db
    # Save the commit id for tracking purposes
    COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/vita-headers-version.txt
    UPDATE_DISCONNECTED ${OFFLINE}
    )

ExternalProject_Add(newlib
    DEPENDS binutils_${target_suffix} gcc-base vita-headers
    GIT_REPOSITORY https://github.com/vitasdk/newlib
    GIT_TAG ${NEWLIB_TAG}
    GIT_SHALLOW 1
    # Pass the compiler_target_tools here so newlib picks up the fresh gcc-base compiler
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${compiler_flag} ${toolchain_tools} ${compiler_target_tools}
    ${wrapper_command} <SOURCE_DIR>/configure "CFLAGS_FOR_TARGET=-g -O2 -ffunction-sections -fdata-sections"
    --build=${build_native}
    --host=${host_native}
    --target=${target_arch}
    # Use this prefix so the install target can be run twice with different paths
    --prefix=/
    --with-build-sysroot=${CMAKE_INSTALL_PREFIX}/${target_arch}
    --enable-newlib-io-long-long
    --enable-newlib-register-fini
    --disable-newlib-supplied-syscalls
    --enable-newlib-long-time_t
    --disable-nls
    --enable-newlib-iconv
    BUILD_COMMAND ${CMAKE_COMMAND} -E env ${compiler_flags} ${toolchain_tools} ${wrapper_command} $(MAKE)
    INSTALL_COMMAND $(MAKE) install DESTDIR=${CMAKE_INSTALL_PREFIX}
    # Install a copy of newlib in the toolchain directory (required for pthread-embedded target)
    COMMAND $(MAKE) install DESTDIR=${toolchain_build_install_dir}
    # Save the commit id for tracking purposes
    COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/newlib-version.txt
    UPDATE_DISCONNECTED ${OFFLINE}
    )

# Build a complete gcc compiler to be able to compile the full gcc for the host when crosscompiling.
# Using gcc-base doesn't work since is missing some headers.
if(CMAKE_TOOLCHAIN_FILE)
    ExternalProject_add(gcc-complete
        DEPENDS newlib gmp_${build_suffix} mpfr_${build_suffix} mpc_${build_suffix} isl_${build_suffix} libelf_${build_suffix} zstd_${build_suffix}
        URL https://ftpmirror.gnu.org/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz
        URL_HASH ${GCC_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        PATCH_COMMAND patch -d <SOURCE_DIR> -p1 -t -N < ${PROJECT_SOURCE_DIR}/patches/gcc/0001-gcc-13-vita.patch
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${compiler_flags} ${toolchain_tools} 
        ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        # compile a native compiler so keep host == build
        --host=${build_native}
        --target=${target_arch}
        --prefix=${toolchain_build_install_dir}
        --libdir=${toolchain_build_install_dir}/lib
        --libexecdir=${toolchain_build_install_dir}/lib
        --with-sysroot=${toolchain_build_install_dir}/${target_arch}
        --with-gmp=${toolchain_build_depends_dir}
        --with-mpfr=${toolchain_build_depends_dir}
        --with-mpc=${toolchain_build_depends_dir}
        --with-isl=${toolchain_build_depends_dir}
        --with-libelf=${toolchain_build_depends_dir}
        --with-zstd=${toolchain_build_depends_dir}
        ${common_gcc_configure_args}
        --enable-threads=posix
        --with-headers=yes
        --enable-libgomp
        "CFLAGS=${GCC_CFLAGS}"
        "CXXFLAGS=${GCC_CFLAGS}"
        BUILD_COMMAND ${CMAKE_COMMAND} -E env ${toolchain_tools} ${wrapper_command} $(MAKE) INHIBIT_LIBC_CFLAGS="-DUSE_TM_CLONE_REGISTRY=0"
        INSTALL_COMMAND $(MAKE) install
        )
    # Add this target as dependency of the final gcc target
    set(GCC_DEPENDS gcc-complete)
else()
    # Just use gcc-base as the dependency of the final gcc target
    set(GCC_DEPENDS gcc-base)
endif()

ExternalProject_Add(pthread-embedded
    DEPENDS binutils_${target_suffix} gcc-base newlib vita-headers
    GIT_REPOSITORY https://github.com/vitasdk/pthread-embedded
    GIT_TAG ${PTHREAD_TAG}
    GIT_SHALLOW 1
    # TODO: this project should have a proper makefile to support out-of-source builds
    BUILD_IN_SOURCE 1
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ${CMAKE_COMMAND} -E env ${compiler_flags} ${wrapper_command} $(MAKE)
    -C <SOURCE_DIR>/platform/vita ${pthread_tools} PREFIX=${CMAKE_INSTALL_PREFIX}
    INSTALL_COMMAND $(MAKE) -C <SOURCE_DIR>/platform/vita PREFIX=${CMAKE_INSTALL_PREFIX}/${target_arch} install
    # Install into the toolchain directory (required for libgomp target)
    COMMAND $(MAKE) install -C <SOURCE_DIR>/platform/vita PREFIX=${toolchain_build_install_dir}/${target_arch} install
    # Save the commit id for tracking purposes
    COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/pthread-embedded-version.txt
    UPDATE_DISCONNECTED ${OFFLINE}
    )

ExternalProject_add(gcc-final
    DEPENDS gmp_${target_suffix} mpfr_${target_suffix} mpc_${target_suffix} isl_${target_suffix} libelf_${target_suffix} zstd_${target_suffix}
    DEPENDS newlib ${GCC_DEPENDS} pthread-embedded
    URL https://ftpmirror.gnu.org/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz
    URL_HASH ${GCC_HASH}
    DOWNLOAD_DIR ${DOWNLOAD_DIR}
    PATCH_COMMAND patch -d <SOURCE_DIR> -p1 -t -N < ${PROJECT_SOURCE_DIR}/patches/gcc/0001-gcc-13-vita.patch
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${compiler_flags} ${toolchain_tools} ${compiler_target_tools}
    ${wrapper_command} <SOURCE_DIR>/configure
    --build=${build_native}
    --host=${host_native}
    --target=${target_arch}
    --prefix=${CMAKE_INSTALL_PREFIX}
    --libdir=${CMAKE_INSTALL_PREFIX}/lib
    --libexecdir=${CMAKE_INSTALL_PREFIX}/lib
    --with-sysroot=${CMAKE_INSTALL_PREFIX}/${target_arch}
    --with-gmp=${toolchain_target_depends_dir}
    --with-mpfr=${toolchain_target_depends_dir}
    --with-mpc=${toolchain_target_depends_dir}
    --with-isl=${toolchain_target_depends_dir}
    --with-libelf=${toolchain_target_depends_dir}
    --with-zstd=${toolchain_target_depends_dir}
    ${common_gcc_configure_args}
    --with-headers=yes
    --enable-threads=posix
    --enable-libgomp
    "CFLAGS=${GCC_CFLAGS}"
    "CXXFLAGS=${GCC_CFLAGS}"
    BUILD_COMMAND ${CMAKE_COMMAND} -E env ${toolchain_tools} ${compiler_target_tools} ${wrapper_command}
    $(MAKE) INHIBIT_LIBC_CFLAGS="-DUSE_TM_CLONE_REGISTRY=0"
    INSTALL_COMMAND $(MAKE) install
    # Remove gcc docs to reduce size
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_INSTALL_PREFIX}/share/man
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_INSTALL_PREFIX}/share/info
    # Remove .la files
    COMMAND ${CMAKE_COMMAND} -DGLOB_PATTERN=${CMAKE_INSTALL_PREFIX}/*.la
    -P ${CMAKE_SOURCE_DIR}/cmake/remove_files.cmake
    )

ExternalProject_Add(samples
    GIT_REPOSITORY https://github.com/vitasdk/samples
    GIT_TAG ${SAMPLES_TAG}
    GIT_SHALLOW 1
    BUILD_IN_SOURCE 1
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ""
    INSTALL_COMMAND ${CMAKE_COMMAND}
    -DGLOB_PATTERN=<SOURCE_DIR> -DINSTALL_DIR=${CMAKE_INSTALL_PREFIX}/share/gcc-${target_arch}
    -P ${CMAKE_SOURCE_DIR}/cmake/install_files.cmake
    # Save the commit id for tracking purposes
    COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/samples-version.txt
    UPDATE_DISCONNECTED ${OFFLINE}
    )

ExternalProject_Add(vdpm
    GIT_REPOSITORY https://github.com/vitasdk/vdpm.git
    GIT_TAG ${VDPM_TAG}
    GIT_SHALLOW 1
    BUILD_IN_SOURCE 1
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ""
    INSTALL_COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_INSTALL_PREFIX}/bin/
    COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/include ${CMAKE_INSTALL_PREFIX}/bin/include
    COMMAND ${CMAKE_COMMAND} -E copy <SOURCE_DIR>/vdpm ${CMAKE_INSTALL_PREFIX}/bin/
    COMMAND ${CMAKE_COMMAND} -E copy <SOURCE_DIR>/vitasdk-update ${CMAKE_INSTALL_PREFIX}/bin/
    UPDATE_DISCONNECTED ${OFFLINE}
    )

ExternalProject_Add(vita-makepkg
    GIT_REPOSITORY https://github.com/vitasdk/vita-makepkg.git
    GIT_TAG ${VITA_MAKEPKG_TAG}
    GIT_SHALLOW 1
    BUILD_IN_SOURCE 1
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ""
    INSTALL_COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_INSTALL_PREFIX}/bin/
    COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/libmakepkg ${CMAKE_INSTALL_PREFIX}/bin/libmakepkg
    COMMAND ${CMAKE_COMMAND} -E copy <SOURCE_DIR>/vita-makepkg ${CMAKE_INSTALL_PREFIX}/bin/
    COMMAND ${CMAKE_COMMAND} -E copy <SOURCE_DIR>/makepkg.conf.sample ${CMAKE_INSTALL_PREFIX}/bin/makepkg.conf
    UPDATE_DISCONNECTED ${OFFLINE}
    )

if(${CMAKE_SYSTEM_NAME} STREQUAL "Windows")
    getgcclib(libwinpthread-1.dll WINPTHREAD_DLL)
    if(WINPTHREAD_DLL)
        add_custom_command(TARGET gcc-final POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy ${WINPTHREAD_DLL} ${CMAKE_INSTALL_PREFIX}/bin/
            COMMENT "Copying libwinpthread-1.dll"
            )
    endif(WINPTHREAD_DLL)
endif()

# Strip toolchain binaries to reduce filesize
add_custom_command(TARGET gcc-final POST_BUILD
    COMMAND ${CMAKE_COMMAND} -DHOST_SYSTEM_NAME=${CMAKE_HOST_SYSTEM_NAME}
    -DBINDIR=${CMAKE_INSTALL_PREFIX}/bin
    -P ${CMAKE_SOURCE_DIR}/cmake/strip_host_binaries.cmake

    COMMAND ${CMAKE_COMMAND} -DHOST_SYSTEM_NAME=${CMAKE_HOST_SYSTEM_NAME}
    -DBINDIR=${CMAKE_INSTALL_PREFIX}/${target_arch}/bin
    -P ${CMAKE_SOURCE_DIR}/cmake/strip_host_binaries.cmake

    COMMAND ${CMAKE_COMMAND} -DHOST_SYSTEM_NAME=${CMAKE_HOST_SYSTEM_NAME}
    -DBINDIR=${CMAKE_INSTALL_PREFIX}/lib/gcc/${target_arch}/${GCC_VERSION}
    -P ${CMAKE_SOURCE_DIR}/cmake/strip_host_binaries.cmake

    COMMENT "Stripping host binaries"
    )

# Remove unnecessary sections from toolchain libraries
add_custom_command(TARGET gcc-final POST_BUILD
    COMMAND ${CMAKE_COMMAND} -DOBJCOPY_COMMAND=${binutils_prefix}-objcopy
    -DPATTERN_GLOB=${CMAKE_INSTALL_PREFIX}/${target_arch}/lib/*.[ao]
    -P ${CMAKE_SOURCE_DIR}/cmake/strip_target_objects.cmake

    COMMAND ${CMAKE_COMMAND} -DOBJCOPY_COMMAND=${binutils_prefix}-objcopy
    -DPATTERN_GLOB=${CMAKE_INSTALL_PREFIX}/lib/gcc/${target_arch}/${GCC_VERSION}/*[!d][!d][!l].[ao]
    -P ${CMAKE_SOURCE_DIR}/cmake/strip_target_objects.cmake

    COMMENT "Stripping target objects"
    )

set(version_info_file ${CMAKE_INSTALL_PREFIX}/version_info.txt)

# Merge the commit ids of the collected projects into a single file
add_custom_command(OUTPUT ${version_info_file}
    COMMAND ${CMAKE_COMMAND} -DINPUT_DIR=${CMAKE_BINARY_DIR} -DOUTPUT_FILE=${version_info_file}
    -P ${CMAKE_SOURCE_DIR}/cmake/create_version.cmake
    DEPENDS vita-headers vita-toolchain_${target_suffix} newlib pthread-embedded samples
    COMMENT "Creating version_info.txt"
    )

add_custom_command(OUTPUT "vitasdk-${host_native}-${build_date}.tar.bz2"
    COMMAND ${CMAKE_COMMAND} -E tar "cfvj" "vitasdk-${host_native}-${build_date}.tar.bz2" "${CMAKE_INSTALL_PREFIX}"
    DEPENDS vita-toolchain_${target_suffix} binutils_${target_suffix} gdb_${target_suffix} vita-headers newlib pthread-embedded samples vdpm vita-makepkg
    DEPENDS gcc-final ${version_info_file}
    COMMENT "Creating vitasdk-${host_os}-${build_date}.tar.bz2"
    )

# Create a sdk tarball
add_custom_target(tarball DEPENDS "vitasdk-${host_native}-${build_date}.tar.bz2")
