#
# Copyright(c) 2016 codestation
# Distributed under the MIT License (http://opensource.org/licenses/MIT)
#

cmake_minimum_required(VERSION 3.2.0)

project(vitasdk)

# Use the following gcc version
set(GCC_VERSION 8.3.0)
set(GCC_HASH SHA256=64baadfe6cc0f4947a84cb12d7f0dfaf45bb58b7e92461639596c21e02d97d2c)

set(ZLIB_VERSION 1.2.11)
set(ZLIB_HASH SHA256=4ff941449631ace0d4d203e3483be9dbc9da454084111f97ea0a2114e19bf066)

set(LIBZIP_VERSION 1.2.0) # Outdated
set(LIBZIP_HASH SHA256=6cf9840e427db96ebf3936665430bab204c9ebbd0120c326459077ed9c907d9f)

set(LIBELF_VERSION 0.8.13)
set(LIBELF_HASH SHA256=591a9b4ec81c1f2042a97aa60564e0cb79d041c52faa7416acb38bc95bd2c76d)

set(LIBYAML_VERSION 0.2.1)
set(LIBYAML_HASH SHA256=78281145641a080fb32d6e7a87b9c0664d611dcb4d542e90baf731f51cbb59cd)

set(GMP_VERSION 6.1.2)
set(GMP_HASH SHA256=5275bb04f4863a13516b2f39392ac5e272f5e1bb8057b18aec1c9b79d73d8fb2)

set(MPFR_VERSION 4.0.2)
set(MPFR_HASH SHA256=c05e3f02d09e0e9019384cdd58e0f19c64e6db1fd6f5ecf77b4b1c61ca253acc)

set(MPC_VERSION 1.1.0)
set(MPC_HASH SHA256=6985c538143c1208dcb1ac42cedad6ff52e267b47e5f970183a3e75125b43c2e)

set(ISL_VERSION 0.20)
set(ISL_HASH SHA256=b587e083eb65a8b394e833dea1744f21af3f0e413a448c17536b5549ae42a4c2)

set(EXPAT_VERSION 2.2.6)
set(EXPAT_HASH SHA256=17b43c2716d521369f82fc2dc70f359860e90fa440bea65b3b85f0b246ea81f2)

set(BINUTILS_VERSION 2.32)
set(BINUTILS_HASH SHA256=0ab6c55dd86a92ed561972ba15b9b70a8b9f75557f896446c82e8b36e473ee04)

set(GDB_VERSION 8.2)
set(GDB_HASH SHA256=c3a441a29c7c89720b734e5a9c6289c0a06be7e0c76ef538f7bbcef389347c39)

# Branches to fetch the different project targets. Can be overriden from command line.
set(NEWLIB_TAG vita CACHE string "newlib branch name, commit id or tag")
set(SAMPLES_TAG master CACHE string "samples branch name, commit id or tag")
set(HEADERS_TAG master CACHE string "vita-headers branch name, commit id or tag")
set(TOOLCHAIN_TAG master CACHE string "vita-toolchain branch name, commit id or tag")
set(PTHREAD_TAG master CACHE string "pthread-embedded branch name, commit id or tag")
set(VDPM_TAG master CACHE string "vdpm branch name, commit id or tag")
set(VITA_MAKEPKG_TAG master CACHE string "vita-makepkg branch name, commit id or tag")

# Location to save the downloaded tarballs. Can be overriden from command line.
set(DOWNLOAD_DIR ${CMAKE_BINARY_DIR}/downloads CACHE PATH "Default download path for tarballs")

set(OFFLINE YES CACHE BOOL "Check repo updates")
set(UPDATE_DISCONNECTED_SUPPORT UPDATE_DISCONNECTED ${OFFLINE})

if("${CMAKE_VERSION}" VERSION_GREATER 3.6.0)
    set(GIT_SHALLOW_SUPPORT GIT_SHALLOW 1)
endif()

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
        URL http://downloads.sourceforge.net/project/libpng/zlib/${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.xz
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
            COMMENT "Delete shared libraries, if present"
            )
    endif()

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
        URL https://github.com/devnoname120/libzip/releases/download/${LIBZIP_VERSION}/libzip-${LIBZIP_VERSION}.tar.gz
        URL_HASH ${LIBZIP_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
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
        PATCH_COMMAND patch -d <SOURCE_DIR> -p3 -t -N < ${PROJECT_SOURCE_DIR}/patches/libelf.patch
        CONFIGURE_COMMAND CC=${cc_compiler} RANLIB=${ranlib} ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --prefix=${toolchain_deps_dir}
        --libdir=${toolchain_deps_dir}/lib
        --disable-shared
        --disable-nls
        )

    ExternalProject_add(libyaml${suffix}
        URL http://pyyaml.org/download/libyaml/yaml-${LIBYAML_VERSION}.tar.gz
        URL_HASH ${LIBYAML_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        CONFIGURE_COMMAND ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --prefix=${toolchain_deps_dir}
        --libdir=${toolchain_deps_dir}/lib
        --disable-shared
        --enable-static
        "CFLAGS=-DYAML_DECLARE_STATIC"
        )

    ExternalProject_add(gmp${suffix}
        URL http://ftp.gnu.org/gnu/gmp/gmp-${GMP_VERSION}.tar.bz2
        URL_HASH ${GMP_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        CONFIGURE_COMMAND CPPFLAGS=-fexceptions ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --prefix=${toolchain_deps_dir}
        --libdir=${toolchain_deps_dir}/lib
        --enable-cxx
        --disable-shared
        BUILD_COMMAND ${compiler_flags} ${wrapper_command} $(MAKE)
        )

    ExternalProject_add(mpfr${suffix}
        DEPENDS gmp${suffix}
        URL http://ftp.gnu.org/gnu/mpfr/mpfr-${MPFR_VERSION}.tar.bz2
        URL_HASH ${MPFR_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        CONFIGURE_COMMAND ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
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
        CONFIGURE_COMMAND ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
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
        URL http://isl.gforge.inria.fr/isl-${ISL_VERSION}.tar.bz2
        URL_HASH ${ISL_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        CONFIGURE_COMMAND ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --prefix=${toolchain_deps_dir}
        --libdir=${toolchain_deps_dir}/lib
        --with-gmp-prefix=${toolchain_deps_dir}
        --disable-shared
        )

    ExternalProject_add(expat${suffix}
        URL http://downloads.sourceforge.net/sourceforge/expat/expat-${EXPAT_VERSION}.tar.bz2
        URL_HASH ${EXPAT_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        CONFIGURE_COMMAND ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
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
        ${GIT_SHALLOW_SUPPORT}
        # Set prefix to "/" here to be able to install twice
        CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=/ ${toolchain_cmake_args}
        -Dlibelf_INCLUDE_DIR=${toolchain_deps_dir}/include
        -Dlibelf_LIBRARY=${toolchain_deps_dir}/lib/libelf.a
        -Dzlib_INCLUDE_DIR=${toolchain_deps_dir}/include
        -Dzlib_LIBRARY=${toolchain_deps_dir}/lib/libz.a
        -Dlibzip_INCLUDE_DIR=${toolchain_deps_dir}/include
        -Dlibzip_CONFIG_INCLUDE_DIR=${toolchain_deps_dir}/lib/libzip/include
        -Dlibzip_LIBRARY=${toolchain_deps_dir}/lib/libzip.a
        -Dlibyaml_INCLUDE_DIR=${toolchain_deps_dir}/include
        -Dlibyaml_LIBRARY=${toolchain_deps_dir}/lib/libyaml.a
        BUILD_COMMAND $(MAKE)
        INSTALL_COMMAND $(MAKE) install DESTDIR=${toolchain_install_dir}
        # Save the commit id for tracking purposes
        COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/vita-toolchain-version.txt
        ${UPDATE_DISCONNECTED_SUPPORT}
        )

    fix_repo_update(vita-toolchain${suffix})

    ExternalProject_Add(binutils${suffix}
        URL https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz
        URL_HASH ${BINUTILS_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        PATCH_COMMAND
            patch -d <SOURCE_DIR> -p3 -t -N < ${PROJECT_SOURCE_DIR}/patches/binutils/0001-vita.patch
            && patch -d <SOURCE_DIR> -p1 -t -N < ${PROJECT_SOURCE_DIR}/patches/binutils/0002-fix-broken-reloc.patch
        CONFIGURE_COMMAND ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
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
        BUILD_COMMAND $(MAKE)
        INSTALL_COMMAND $(MAKE) install DESTDIR=${toolchain_install_dir}
        )

    ExternalProject_Add(gdb${suffix}
        URL https://ftp.gnu.org/gnu/gdb/gdb-${GDB_VERSION}.tar.xz
        URL_HASH ${GDB_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        CONFIGURE_COMMAND ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --target=${target_arch}
        # Set prefix to "/" here to be able to install twice
        --prefix=/
        --with-sysroot=${toolchain_install_dir}
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

# Prevent GCC wrapping system includes in extern "C" (modern systems should define this)
set(GCC_CFLAGS "-DNO_IMPLICIT_EXTERN_C")

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
    "--with-pkgversion=${pkgversion}"
    )

if("${CMAKE_CXX_COMPILER_ID}" STREQUAL "GNU")
    list(APPEND common_gcc_configure_args "--with-host-libstdcxx=-static-libgcc -Wl,-Bstatic,-lstdc++,-Bdynamic -lm")
endif()

# Build a basic gcc compiler, needed to compile newlib
ExternalProject_add(gcc-base
    DEPENDS gmp_${build_suffix} mpfr_${build_suffix} mpc_${build_suffix} isl_${build_suffix}
    URL http://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz
    URL_HASH ${GCC_HASH}
    DOWNLOAD_DIR ${DOWNLOAD_DIR}
    PATCH_COMMAND patch -d <SOURCE_DIR> -p3 -t -N < ${PROJECT_SOURCE_DIR}/patches/gcc/0001-gcc-8.patch
    CONFIGURE_COMMAND ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
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
    ${common_gcc_configure_args}
    --disable-threads
    --without-headers
    "CFLAGS=${GCC_CFLAGS}"
    "CXXFLAGS=${GCC_CFLAGS}"
    BUILD_COMMAND $(MAKE) all-gcc
    INSTALL_COMMAND $(MAKE) install-gcc
    )

ExternalProject_add(vita-headers
    DEPENDS binutils_${build_suffix} vita-toolchain_${build_suffix}
    GIT_REPOSITORY https://github.com/vitasdk/vita-headers
    GIT_TAG ${HEADERS_TAG}
    ${GIT_SHALLOW_SUPPORT}
    # TODO: vita-libs-gen should generate a proper makefile so this can be simplified
    CONFIGURE_COMMAND ${vita_libs_gen_command} <SOURCE_DIR>/db.yml <BINARY_DIR>
    BUILD_COMMAND $(MAKE) ARCH=${binutils_prefix}
    # Copy the generated .a files to the install directory
    INSTALL_COMMAND ${CMAKE_COMMAND} -DGLOB_PATTERN=<BINARY_DIR>/*a
    -DINSTALL_DIR=${CMAKE_INSTALL_PREFIX}/${target_arch}/lib
    -P ${CMAKE_SOURCE_DIR}/cmake/install_files.cmake
    # Copy the include headers to the installation directory
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_INSTALL_PREFIX}/${target_arch}/include
    COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/include ${CMAKE_INSTALL_PREFIX}/${target_arch}/include
    # Install a copy of the headers in the toolchain directory (required for pthread-embedded target)
    COMMAND ${CMAKE_COMMAND} -E make_directory ${toolchain_build_install_dir}/${target_arch}/include
    COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/include ${toolchain_build_install_dir}/${target_arch}/include
    # Copy the yml database to the installation directory
    COMMAND ${CMAKE_COMMAND} -DGLOB_PATTERN=<SOURCE_DIR>/db.yml -DINSTALL_DIR=${CMAKE_INSTALL_PREFIX}/share
    -P ${CMAKE_SOURCE_DIR}/cmake/install_files.cmake
    # Save the commit id for tracking purposes
    COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/vita-headers-version.txt
    ${UPDATE_DISCONNECTED_SUPPORT}
    )

fix_repo_update(vita-headers)

ExternalProject_Add(newlib
    DEPENDS binutils_${target_suffix} gcc-base vita-headers
    GIT_REPOSITORY https://github.com/vitasdk/newlib
    GIT_TAG ${NEWLIB_TAG}
    ${GIT_SHALLOW_SUPPORT}
    # Pass the compiler_target_tools here so newlib picks up the fresh gcc-base compiler
    CONFIGURE_COMMAND ${compiler_flags} ${toolchain_tools} ${compiler_target_tools}
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
    --disable-nls
    BUILD_COMMAND ${compiler_flags} ${toolchain_tools} ${wrapper_command} $(MAKE)
    INSTALL_COMMAND $(MAKE) install DESTDIR=${CMAKE_INSTALL_PREFIX}
    # Install a copy of newlib in the toolchain directory (required for pthread-embedded target)
    COMMAND $(MAKE) install DESTDIR=${toolchain_build_install_dir}
    # Save the commit id for tracking purposes
    COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/newlib-version.txt
    ${UPDATE_DISCONNECTED_SUPPORT}
    )

fix_repo_update(newlib)

# Build a complete gcc compiler to be able to compile the full gcc for the host when crosscompiling.
# Using gcc-base doesn't work since is missing some headers.
if(CMAKE_TOOLCHAIN_FILE)
    ExternalProject_add(gcc-complete
        DEPENDS newlib gmp_${build_suffix} mpfr_${build_suffix} mpc_${build_suffix} isl_${build_suffix}
        URL http://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz
        URL_HASH ${GCC_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        PATCH_COMMAND patch -d <SOURCE_DIR> -p3 -t -N < ${PROJECT_SOURCE_DIR}/patches/gcc/0001-gcc-8.patch
        CONFIGURE_COMMAND ${compiler_flags} ${toolchain_tools}
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
        ${common_gcc_configure_args}
        --disable-threads
        --with-headers=yes
        "CFLAGS=${GCC_CFLAGS}"
        "CXXFLAGS=${GCC_CFLAGS}"
        BUILD_COMMAND ${toolchain_tools} ${wrapper_command} $(MAKE) INHIBIT_LIBC_CFLAGS="-DUSE_TM_CLONE_REGISTRY=0"
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
    ${GIT_SHALLOW_SUPPORT}
    # TODO: this project should have a proper makefile to support out-of-source builds
    BUILD_IN_SOURCE 1
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ${compiler_flags} ${wrapper_command} $(MAKE)
    -C <SOURCE_DIR>/platform/vita ${pthread_tools} PREFIX=${CMAKE_INSTALL_PREFIX}
    INSTALL_COMMAND $(MAKE) -C <SOURCE_DIR>/platform/vita PREFIX=${CMAKE_INSTALL_PREFIX}/${target_arch} install
    # Save the commit id for tracking purposes
    COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/pthread-embedded-version.txt
    ${UPDATE_DISCONNECTED_SUPPORT}
    )

fix_repo_update(pthread-embedded)

ExternalProject_add(gcc-final
    DEPENDS gmp_${target_suffix} mpfr_${target_suffix} mpc_${target_suffix} isl_${target_suffix}
    DEPENDS newlib ${GCC_DEPENDS} pthread-embedded
    URL http://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz
    URL_HASH ${GCC_HASH}
    DOWNLOAD_DIR ${DOWNLOAD_DIR}
    PATCH_COMMAND patch -d <SOURCE_DIR> -p3 -t -N < ${PROJECT_SOURCE_DIR}/patches/gcc/0001-gcc-8.patch
    CONFIGURE_COMMAND ${compiler_flags} ${toolchain_tools} ${compiler_target_tools}
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
    ${common_gcc_configure_args}
    --with-headers=yes
    --enable-threads=posix
    "CFLAGS=${GCC_CFLAGS}"
    "CXXFLAGS=${GCC_CFLAGS}"
    BUILD_COMMAND ${toolchain_tools} ${compiler_target_tools} ${wrapper_command}
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
    ${GIT_SHALLOW_SUPPORT}
    BUILD_IN_SOURCE 1
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ""
    INSTALL_COMMAND ${CMAKE_COMMAND}
    -DGLOB_PATTERN=<SOURCE_DIR> -DINSTALL_DIR=${CMAKE_INSTALL_PREFIX}/share/gcc-${target_arch}
    -P ${CMAKE_SOURCE_DIR}/cmake/install_files.cmake
    # Save the commit id for tracking purposes
    COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/samples-version.txt
    ${UPDATE_DISCONNECTED_SUPPORT}
    )

fix_repo_update(samples)

ExternalProject_Add(vdpm
    GIT_REPOSITORY https://github.com/vitasdk/vdpm.git
    GIT_TAG ${VDPM_TAG}
    ${GIT_SHALLOW_SUPPORT}
    BUILD_IN_SOURCE 1
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ""
    INSTALL_COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_INSTALL_PREFIX}/bin/
    COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/include ${CMAKE_INSTALL_PREFIX}/bin/include
    COMMAND ${CMAKE_COMMAND} -E copy <SOURCE_DIR>/vdpm ${CMAKE_INSTALL_PREFIX}/bin/
    COMMAND ${CMAKE_COMMAND} -E copy <SOURCE_DIR>/vitasdk-update ${CMAKE_INSTALL_PREFIX}/bin/
    ${UPDATE_DISCONNECTED_SUPPORT}
    )

fix_repo_update(vdpm)

ExternalProject_Add(vita-makepkg
    GIT_REPOSITORY https://github.com/vitasdk/vita-makepkg.git
    GIT_TAG ${VITA_MAKEPKG_TAG}
    ${GIT_SHALLOW_SUPPORT}
    BUILD_IN_SOURCE 1
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ""
    INSTALL_COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_INSTALL_PREFIX}/bin/
    COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/libmakepkg ${CMAKE_INSTALL_PREFIX}/bin/libmakepkg
    COMMAND ${CMAKE_COMMAND} -E copy <SOURCE_DIR>/vita-makepkg ${CMAKE_INSTALL_PREFIX}/bin/
    COMMAND ${CMAKE_COMMAND} -E copy <SOURCE_DIR>/makepkg.conf.sample ${CMAKE_INSTALL_PREFIX}/bin/makepkg.conf
    ${UPDATE_DISCONNECTED_SUPPORT}
    )

fix_repo_update(vita-makepkg)

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
