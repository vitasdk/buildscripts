#
# Copyright(c) 2016 codestation
# Distributed under the MIT License (http://opensource.org/licenses/MIT)
#

cmake_minimum_required(VERSION 3.16)

project(vitasdk)

# ccache support
find_program(CCACHE_PROGRAM ccache)
if(CCACHE_PROGRAM)
    set(CMAKE_C_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
    set(CMAKE_CXX_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
endif()

include(cmake/Components.cmake)
include(cmake/StaticPolicy.cmake)

# Location to save the downloaded tarballs. Can be overriden from command line.
set(DOWNLOAD_DIR ${CMAKE_BINARY_DIR}/downloads CACHE PATH "Default download path for tarballs")

set(OFFLINE YES CACHE BOOL "Disable updates for Git-backed ExternalProject sources")
set(UPDATE_DISCONNECTED_SUPPORT UPDATE_DISCONNECTED ${OFFLINE})

# Fetch only the selected branch or tag tip for every Git-backed source.
# ExternalProject translates this to a depth-1 clone.
set(GIT_SHALLOW_SUPPORT GIT_SHALLOW TRUE)

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
string(TIMESTAMP default_package_version "0.%Y%m%d.%H%M%S" UTC)
string(TIMESTAMP default_source_date_epoch "%s" UTC)

set(VITASDK_PACKAGE_VERSION "${default_package_version}" CACHE STRING
    "Version used for the vitasdk-core package")
set(VITASDK_SOURCE_DATE_EPOCH "${default_source_date_epoch}" CACHE STRING
    "Reproducible timestamp used for SDK package metadata")
set(VITASDK_SOURCE_REVISION "" CACHE STRING
    "Exact buildscripts Git revision recorded in SDK package metadata")

if(NOT VITASDK_SOURCE_REVISION)
    execute_process(
        COMMAND ${GIT_EXECUTABLE} -C ${PROJECT_SOURCE_DIR} rev-parse HEAD
        OUTPUT_VARIABLE VITASDK_SOURCE_REVISION
        OUTPUT_STRIP_TRAILING_WHITESPACE
        COMMAND_ERROR_IS_FATAL ANY)
endif()

include(Utils)
include(GetTriplet)
include(ExternalProject)

set(vitasdk_base_c_flags "${CMAKE_C_FLAGS}")
set(vitasdk_base_cxx_flags "${CMAKE_CXX_FLAGS}")
set(vitasdk_base_link_flags "${CMAKE_EXE_LINKER_FLAGS}")
vitasdk_get_host_static_flags("${CMAKE_SYSTEM_NAME}"
    host_static_c_flags host_static_cxx_flags host_static_link_flags)
vitasdk_append_flags(CMAKE_C_FLAGS ${host_static_c_flags})
vitasdk_append_flags(CMAKE_CXX_FLAGS ${host_static_cxx_flags})
vitasdk_append_flags(CMAKE_EXE_LINKER_FLAGS ${host_static_link_flags})

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
    set(toolchain_cmake_args)
    set(libelf_patch_series
        "${PROJECT_SOURCE_DIR}/patches/libelf-configure-in.patch|1")
    set(binutils_patch_series
        "${PROJECT_SOURCE_DIR}/patches/binutils/0001-vita.patch|1"
        "${PROJECT_SOURCE_DIR}/patches/binutils/0002-fix-broken-reloc.patch|1"
        "${PROJECT_SOURCE_DIR}/patches/binutils/0003-fix-elf-vaddr.patch|1"
        "${PROJECT_SOURCE_DIR}/patches/binutils/0004-fix-interworking-veneers.patch|3"
        "${PROJECT_SOURCE_DIR}/patches/binutils/0004-fix-zlib-macOS.patch|1")
    set(gdb_patch_series
        "${PROJECT_SOURCE_DIR}/patches/gdb.patch|1"
        "${PROJECT_SOURCE_DIR}/patches/gdb-zlib.patch|1"
        "${PROJECT_SOURCE_DIR}/patches/gdb/0001-clang-enum-flags.patch|1")
    list(JOIN libelf_patch_series "^" libelf_patch_series_arg)
    list(JOIN binutils_patch_series "^" binutils_patch_series_arg)
    list(JOIN gdb_patch_series "^" gdb_patch_series_arg)

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
        set(dependency_c_flags "${CMAKE_C_FLAGS}")
        set(dependency_cxx_flags "${CMAKE_CXX_FLAGS}")
        set(dependency_link_flags "${CMAKE_EXE_LINKER_FLAGS}")
    else()
        # Use the same host triplet as the build env
        set(toolchain_host ${build_native})
        # Use the default toolchain
        set(cc_compiler "gcc")
        set(ranlib "ranlib")
        vitasdk_get_host_static_flags("${CMAKE_HOST_SYSTEM_NAME}"
            build_static_c_flags build_static_cxx_flags build_static_link_flags)
        set(dependency_c_flags "${vitasdk_base_c_flags}")
        set(dependency_cxx_flags "${vitasdk_base_cxx_flags}")
        set(dependency_link_flags "${vitasdk_base_link_flags}")
        vitasdk_append_flags(dependency_c_flags ${build_static_c_flags})
        vitasdk_append_flags(dependency_cxx_flags ${build_static_cxx_flags})
        vitasdk_append_flags(dependency_link_flags ${build_static_link_flags})
    endif()

    list(APPEND toolchain_cmake_args
        "-DCMAKE_C_FLAGS=${dependency_c_flags}"
        "-DCMAKE_CXX_FLAGS=${dependency_cxx_flags}"
        "-DCMAKE_EXE_LINKER_FLAGS=${dependency_link_flags}")

    set(suffix "_${toolchain_suffix}")

    if(toolchain_file AND CMAKE_SYSTEM_NAME STREQUAL "Windows")
        set(zlib_static_archive <BINARY_DIR>/libzlibstatic.a)
    else()
        set(zlib_static_archive <BINARY_DIR>/libz.a)
    endif()
    ExternalProject_Add(zlib${suffix}
        URL ${ZLIB_URL}
        URL_HASH ${ZLIB_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=${toolchain_deps_dir}
        ${toolchain_cmake_args}
        -DBUILD_SHARED_LIBS=OFF
        -DZLIB_BUILD_EXAMPLES=OFF
        BUILD_COMMAND ${CMAKE_COMMAND} --build <BINARY_DIR> --target zlibstatic
        INSTALL_COMMAND ${CMAKE_COMMAND} -E make_directory
            ${toolchain_deps_dir}/include ${toolchain_deps_dir}/lib/pkgconfig
        COMMAND ${CMAKE_COMMAND} -E copy
            ${zlib_static_archive} ${toolchain_deps_dir}/lib/libz.a
        COMMAND ${CMAKE_COMMAND} -E copy
            <SOURCE_DIR>/zlib.h <BINARY_DIR>/zconf.h ${toolchain_deps_dir}/include
        COMMAND ${CMAKE_COMMAND} -E copy
            <BINARY_DIR>/zlib.pc ${toolchain_deps_dir}/lib/pkgconfig/zlib.pc
        )

    list(APPEND toolchain_cmake_args -DBUILD_SHARED_LIBS=OFF)

    # vita-toolchain consumes libzip only as a static archive, so every optional
    # crypto, compression, tool, test, fuzzer, example and documentation feature
    # is disabled explicitly instead of relying on the upstream defaults, which
    # enable all of them. libzip uses GNUInstallDirs, so the library directory is
    # pinned to "lib" to keep the archive path predictable on hosts that would
    # otherwise select lib64.
    ExternalProject_Add(libzip${suffix}
        DEPENDS zlib${suffix}
        URL ${LIBZIP_URL}
        URL_HASH ${LIBZIP_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=${toolchain_deps_dir}
        ${toolchain_cmake_args}
        -DCMAKE_INSTALL_LIBDIR=lib
        -DZLIB_INCLUDE_DIR=${toolchain_deps_dir}/include
        -DZLIB_LIBRARY=${toolchain_deps_dir}/lib/libz.a
        -DENABLE_COMMONCRYPTO=OFF
        -DENABLE_GNUTLS=OFF
        -DENABLE_MBEDTLS=OFF
        -DENABLE_OPENSSL=OFF
        -DENABLE_WINDOWS_CRYPTO=OFF
        -DENABLE_BZIP2=OFF
        -DENABLE_LZMA=OFF
        -DENABLE_ZSTD=OFF
        -DBUILD_TOOLS=OFF
        -DBUILD_REGRESS=OFF
        -DBUILD_OSSFUZZ=OFF
        -DBUILD_EXAMPLES=OFF
        -DBUILD_DOC=OFF
        )

    # USE_BUNDLED_ENDIAN_H is a vita-toolchain option rather than a libzip one,
    # so it is appended after libzip is declared and never reaches a project that
    # does not define it.
    if(NOT ${CMAKE_SYSTEM_NAME} STREQUAL "Windows")
        list(APPEND toolchain_cmake_args -DUSE_BUNDLED_ENDIAN_H=ON)
    endif()

    ExternalProject_add(libelf${suffix}
        DEPENDS zlib${suffix}
        URL ${LIBELF_URL}
        URL_HASH ${LIBELF_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        PATCH_COMMAND ${CMAKE_COMMAND}
            -DSOURCE_DIR=<SOURCE_DIR>
            "-DPATCH_SERIES=${libelf_patch_series_arg}"
            -P ${PROJECT_SOURCE_DIR}/cmake/ApplyPatches.cmake
        COMMAND autoreconf -i <SOURCE_DIR>
        COMMAND ${CMAKE_COMMAND} -E copy
            ${PROJECT_SOURCE_DIR}/config.guess
            ${PROJECT_SOURCE_DIR}/config.sub
            <SOURCE_DIR>/
        CONFIGURE_COMMAND CC=${cc_compiler} RANLIB=${ranlib} ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --prefix=${toolchain_deps_dir}
        --libdir=${toolchain_deps_dir}/lib
        --disable-shared
        --disable-nls
        )

    ExternalProject_add(libyaml${suffix}
        URL ${LIBYAML_URL}
        URL_HASH ${LIBYAML_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        PATCH_COMMAND ${CMAKE_COMMAND} -E copy ${PROJECT_SOURCE_DIR}/config.guess ${PROJECT_SOURCE_DIR}/config.sub <SOURCE_DIR>/config/
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
        URL ${GMP_URL}
        URL_HASH ${GMP_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        CONFIGURE_COMMAND CFLAGS=-std=gnu99 CPPFLAGS=-fexceptions ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --prefix=${toolchain_deps_dir}
        --libdir=${toolchain_deps_dir}/lib
        --enable-cxx
        --disable-shared
        --enable-static
        BUILD_COMMAND ${compiler_flags} ${wrapper_command} $(MAKE)
        )

    ExternalProject_add(mpfr${suffix}
        DEPENDS gmp${suffix}
        URL ${MPFR_URL}
        URL_HASH ${MPFR_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        CONFIGURE_COMMAND ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --prefix=${toolchain_deps_dir}
        --libdir=${toolchain_deps_dir}/lib
        --with-gmp=${toolchain_deps_dir}
        --disable-shared
        --enable-static
        )

    ExternalProject_add(mpc${suffix}
        DEPENDS gmp${suffix} mpfr${suffix}
        URL ${MPC_URL}
        URL_HASH ${MPC_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        CONFIGURE_COMMAND ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --prefix=${toolchain_deps_dir}
        --libdir=${toolchain_deps_dir}/lib
        --with-gmp=${toolchain_deps_dir}
        --with-mpfr=${toolchain_deps_dir}
        --disable-shared
        --enable-static
        --disable-nls
        )

    ExternalProject_add(isl${suffix}
        DEPENDS gmp${suffix}
        GIT_REPOSITORY ${ISL_REPOSITORY}
        GIT_TAG ${ISL_TAG}
        ${GIT_SHALLOW_SUPPORT}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        GIT_SUBMODULES ""
        PATCH_COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR>
            submodule update --init --recursive --depth 1
        COMMAND ${CMAKE_COMMAND} -E chdir <SOURCE_DIR> ./autogen.sh
        CONFIGURE_COMMAND ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --prefix=${toolchain_deps_dir}
        --libdir=${toolchain_deps_dir}/lib
        --with-gmp-prefix=${toolchain_deps_dir}
        --disable-shared
        --enable-static
        ${UPDATE_DISCONNECTED_SUPPORT}
        )

    ExternalProject_add(expat${suffix}
        URL ${EXPAT_URL}
        URL_HASH ${EXPAT_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        CONFIGURE_COMMAND ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --prefix=${toolchain_deps_dir}
        --libdir=${toolchain_deps_dir}/lib
        --disable-shared
        --enable-static
        )

    ExternalProject_Add(vita-toolchain${suffix}
        DEPENDS libelf${suffix} zlib${suffix} libzip${suffix} libyaml${suffix}
        GIT_REPOSITORY ${TOOLCHAIN_REPOSITORY}
        GIT_TAG ${TOOLCHAIN_TAG}
        ${GIT_SHALLOW_SUPPORT}
        # ExternalProject's GIT_SHALLOW only applies to the top-level clone.
        # Initialize this required submodule explicitly at depth 1 as well.
        GIT_SUBMODULES ""
        PATCH_COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR>
            submodule update --init --recursive --depth 1
        # Set prefix to "/" here to be able to install twice
        CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=/ ${toolchain_cmake_args}
        -DTOOLCHAIN_DEPS_DIR=${toolchain_deps_dir}
        -Dlibelf_LIBRARY=${toolchain_deps_dir}/lib/libelf.a
        -Dzlib_LIBRARY=${toolchain_deps_dir}/lib/libz.a
        -Dlibzip_LIBRARY=${toolchain_deps_dir}/lib/libzip.a
        -Dlibyaml_LIBRARY=${toolchain_deps_dir}/lib/libyaml.a
        BUILD_COMMAND $(MAKE)
        INSTALL_COMMAND $(MAKE) install DESTDIR=${toolchain_install_dir}
        # Save the commit id for tracking purposes
        COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/vita-toolchain-version.txt
        ${UPDATE_DISCONNECTED_SUPPORT}
        )

    ExternalProject_Add(binutils${suffix}
        DEPENDS zlib${suffix}
        URL ${BINUTILS_URL}
        URL_HASH ${BINUTILS_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        PATCH_COMMAND ${CMAKE_COMMAND}
            -DSOURCE_DIR=<SOURCE_DIR>
            "-DPATCH_SERIES=${binutils_patch_series_arg}"
            -P ${PROJECT_SOURCE_DIR}/cmake/ApplyPatches.cmake
        COMMAND ${CMAKE_COMMAND} -E copy
            ${PROJECT_SOURCE_DIR}/config.guess
            ${PROJECT_SOURCE_DIR}/config.sub
            <SOURCE_DIR>/
        CONFIGURE_COMMAND CFLAGS=-std=gnu11 ${compiler_flags}
        ${wrapper_command} <SOURCE_DIR>/configure
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
        --without-zstd
        "--with-pkgversion=${pkgversion}"
        BUILD_COMMAND $(MAKE) INFO_DEPS= DVIS= pdfs= htmls=
        INSTALL_COMMAND $(MAKE) install DESTDIR=${toolchain_install_dir} INFO_DEPS= DVIS= pdfs= htmls=
        )

    ExternalProject_Add(gdb${suffix}
        DEPENDS zlib${suffix} gmp${suffix} mpfr${suffix} expat${suffix}
        URL ${GDB_URL}
        URL_HASH ${GDB_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        PATCH_COMMAND ${CMAKE_COMMAND}
            -DSOURCE_DIR=<SOURCE_DIR>
            "-DPATCH_SERIES=${gdb_patch_series_arg}"
            -P ${PROJECT_SOURCE_DIR}/cmake/ApplyPatches.cmake
        COMMAND ${CMAKE_COMMAND} -E copy
            ${PROJECT_SOURCE_DIR}/config.guess
            ${PROJECT_SOURCE_DIR}/config.sub
            <SOURCE_DIR>/
        CONFIGURE_COMMAND CFLAGS=-std=gnu11
        ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --target=${target_arch}
        # Set prefix to "/" here to be able to install twice
        --prefix=/
        --with-sysroot=${toolchain_install_dir}
        --without-system-zlib
        --without-system-readline
        --disable-tui
        --without-zstd
        --without-python
        --without-guile
        --without-lzma
        --without-babeltrace
        --without-xxhash
        --without-debuginfod
        --with-gmp=${toolchain_deps_dir}
        --with-mpfr=${toolchain_deps_dir}
        --with-expat
        --with-libexpat-prefix=${toolchain_deps_dir}
        --with-libexpat-type=static
        # GDB provides stub-termcap when tgetent is unavailable. Propagate both
        # cache answers to the GDB and bundled Readline sub-configures so they
        # cannot auto-link the runner's libtinfo/ncurses.
        "host_configargs=ac_cv_search_tgetent=no bash_cv_termcap_lib=libc"
        BUILD_COMMAND $(MAKE) INFO_DEPS= DVIS= pdfs= htmls=
        INSTALL_COMMAND $(MAKE) install DESTDIR=${toolchain_install_dir} INFO_DEPS= DVIS= pdfs= htmls=
        )

    # Install binutils, gdb and vita-toolchain on CMAKE_INSTALL_PREFIX when not crosscompiling
    if(NOT toolchain_file AND "${host_native}" STREQUAL "${build_native}")
        ExternalProject_Add_Step(binutils${suffix}
            install_sdk
            DEPENDEES install
            COMMAND $(MAKE) -C <BINARY_DIR> install DESTDIR=${CMAKE_INSTALL_PREFIX}
            COMMENT "Installing binutils to ${CMAKE_INSTALL_PREFIX}"
            )

        ExternalProject_Add_Step(gdb${suffix}
            install_sdk
            DEPENDEES install
            COMMAND $(MAKE) -C <BINARY_DIR> install DESTDIR=${CMAKE_INSTALL_PREFIX}
            COMMENT "Installing gdb to ${CMAKE_INSTALL_PREFIX}"
            )

        ExternalProject_Add_Step(vita-toolchain${suffix}
            install_sdk
            DEPENDEES install
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

option(BUILD_PACMAN_CLIENT "Build the package client provided by vdpm" OFF)
set(PACMAN_CLIENT_INSTALL_DIR "${CMAKE_INSTALL_PREFIX}"
    CACHE PATH "Install directory for the vdpm package client")
set(VDPM_BUNDLE "" CACHE FILEPATH
    "Verified vdpm host component bundle incorporated into the SDK")
set(VDPM_BUNDLE_SHA256 "" CACHE STRING
    "SHA-256 of VDPM_BUNDLE")
set(VDPM_MESON_EXECUTABLE "" CACHE FILEPATH
    "Optional Meson executable forwarded to the vdpm component")

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
    GLOBAL_CFLAGS=-Wno-error=int-conversion
    )

set(GCC_CFLAGS)
set(gcc_patch_series
    "${PROJECT_SOURCE_DIR}/patches/gcc/0001-gcc-15.patch|1")
list(JOIN gcc_patch_series "^" gcc_patch_series_arg)
if("${CMAKE_CXX_COMPILER_ID}" MATCHES "Clang" AND ${CMAKE_SYSTEM_NAME} STREQUAL "Darwin")
    # GCC on OSX (Clang in diguise) needs more bracket nesting depth to compile gcc
    set(GCC_CFLAGS "${GCC_CFLAGS} -fbracket-depth=512")
endif()

# Common gcc configure options
set(common_gcc_configure_args
    --with-python-dir=share/gcc-${target_arch}
    --enable-languages=c,c++
    --disable-decimal-float
    # libcc1 only implements GDB's optional "compile" command and installs
    # host shared objects that would make the SDK depend on the build host's
    # C++ runtime. It is not part of the Vita compiler contract.
    --disable-libcc1
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
    # Do not auto-detect the runner's shared zstd. Optional zstd compression
    # is outside the toolchain contract and would make the SDK non-relocatable.
    --without-zstd
    --disable-multilib
    --with-arch=armv7-a
    --with-tune=cortex-a9
    --with-fpu=neon
    --with-float=hard
    --with-mode=thumb
    "--with-pkgversion=${pkgversion}"
    )

if("${CMAKE_CXX_COMPILER_ID}" STREQUAL "GNU")
    list(APPEND common_gcc_configure_args
        "--with-host-libstdcxx=-static-libgcc -static-libstdc++ -lm")
endif()

# Build a basic gcc compiler, needed to compile newlib
ExternalProject_add(gcc-base
    DEPENDS gmp_${build_suffix} mpfr_${build_suffix} mpc_${build_suffix} isl_${build_suffix} libelf_${build_suffix}
    URL ${GCC_URL}
    URL_HASH ${GCC_HASH}
    DOWNLOAD_DIR ${DOWNLOAD_DIR}
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    PATCH_COMMAND ${CMAKE_COMMAND}
        -DSOURCE_DIR=<SOURCE_DIR>
        "-DPATCH_SERIES=${gcc_patch_series_arg}"
        -P ${PROJECT_SOURCE_DIR}/cmake/ApplyPatches.cmake
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
    --disable-libgomp
    "CFLAGS=${GCC_CFLAGS}"
    "CXXFLAGS=${GCC_CFLAGS}"
    BUILD_COMMAND $(MAKE) all-gcc
    INSTALL_COMMAND $(MAKE) install-gcc
    )

ExternalProject_add(vita-headers
    DEPENDS binutils_${build_suffix} vita-toolchain_${build_suffix}
    GIT_REPOSITORY ${HEADERS_REPOSITORY}
    GIT_TAG ${HEADERS_TAG}
    ${GIT_SHALLOW_SUPPORT}
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
    ${UPDATE_DISCONNECTED_SUPPORT}
    )

ExternalProject_Add(newlib
    DEPENDS binutils_${target_suffix} gcc-base vita-headers
    GIT_REPOSITORY ${NEWLIB_REPOSITORY}
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
    --enable-newlib-long-time_t
    --disable-nls
    --enable-newlib-iconv
    BUILD_COMMAND ${compiler_flags} ${toolchain_tools} ${wrapper_command} $(MAKE)
    INSTALL_COMMAND $(MAKE) install DESTDIR=${CMAKE_INSTALL_PREFIX}
    # Install a copy of newlib in the toolchain directory (required for pthread-embedded target)
    COMMAND $(MAKE) install DESTDIR=${toolchain_build_install_dir}
    # Save the commit id for tracking purposes
    COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/newlib-version.txt
    ${UPDATE_DISCONNECTED_SUPPORT}
    )

# Build a complete gcc compiler to be able to compile the full gcc for the host when crosscompiling.
# Using gcc-base doesn't work since is missing some headers.
if(CMAKE_TOOLCHAIN_FILE)
    ExternalProject_add(gcc-complete
        DEPENDS newlib gmp_${build_suffix} mpfr_${build_suffix} mpc_${build_suffix} isl_${build_suffix} libelf_${build_suffix}
        URL ${GCC_URL}
        URL_HASH ${GCC_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        PATCH_COMMAND ${CMAKE_COMMAND}
            -DSOURCE_DIR=<SOURCE_DIR>
            "-DPATCH_SERIES=${gcc_patch_series_arg}"
            -P ${PROJECT_SOURCE_DIR}/cmake/ApplyPatches.cmake
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
        --enable-threads=posix
        --with-headers=yes
        --enable-libgomp
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
    GIT_REPOSITORY ${PTHREAD_REPOSITORY}
    GIT_TAG ${PTHREAD_TAG}
    ${GIT_SHALLOW_SUPPORT}
    # TODO: this project should have a proper makefile to support out-of-source builds
    BUILD_IN_SOURCE 1
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ${compiler_flags} ${wrapper_command} $(MAKE)
    -C <SOURCE_DIR>/platform/vita ${pthread_tools} PREFIX=${CMAKE_INSTALL_PREFIX}
    INSTALL_COMMAND $(MAKE) -C <SOURCE_DIR>/platform/vita PREFIX=${CMAKE_INSTALL_PREFIX}/${target_arch} install
    # Install into the toolchain directory (required for libgomp target)
    COMMAND $(MAKE) install -C <SOURCE_DIR>/platform/vita PREFIX=${toolchain_build_install_dir}/${target_arch} install
    # Save the commit id for tracking purposes
    COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/pthread-embedded-version.txt
    ${UPDATE_DISCONNECTED_SUPPORT}
    )

ExternalProject_add(gcc-final
    DEPENDS gmp_${target_suffix} mpfr_${target_suffix} mpc_${target_suffix} isl_${target_suffix} libelf_${target_suffix}
    DEPENDS newlib ${GCC_DEPENDS} pthread-embedded
    URL ${GCC_URL}
    URL_HASH ${GCC_HASH}
    DOWNLOAD_DIR ${DOWNLOAD_DIR}
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    PATCH_COMMAND ${CMAKE_COMMAND}
        -DSOURCE_DIR=<SOURCE_DIR>
        "-DPATCH_SERIES=${gcc_patch_series_arg}"
        -P ${PROJECT_SOURCE_DIR}/cmake/ApplyPatches.cmake
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
    --enable-libgomp
    "CFLAGS=${GCC_CFLAGS}"
    "CXXFLAGS=${GCC_CFLAGS}"
    BUILD_COMMAND ${toolchain_tools} ${compiler_target_tools} ${wrapper_command}
    $(MAKE) INHIBIT_LIBC_CFLAGS="-DUSE_TM_CLONE_REGISTRY=0"
    INSTALL_COMMAND $(MAKE) install
    )

ExternalProject_Add(samples
    GIT_REPOSITORY ${SAMPLES_REPOSITORY}
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

set(vdpm_use_release_bundle OFF)
if(BUILD_PACMAN_CLIENT AND (VDPM_BUNDLE OR VDPM_BUNDLE_SHA256))
    if(NOT VDPM_BUNDLE OR NOT VDPM_BUNDLE_SHA256)
        message(FATAL_ERROR
            "VDPM_BUNDLE and VDPM_BUNDLE_SHA256 must be supplied together")
    endif()
    set(vdpm_use_release_bundle ON)
endif()
if(CMAKE_SYSTEM_NAME STREQUAL "Windows" AND BUILD_PACMAN_CLIENT AND NOT vdpm_use_release_bundle)
    message(FATAL_ERROR
        "Windows package-client builds require VDPM_BUNDLE and VDPM_BUNDLE_SHA256")
endif()
set(vdpm_build_package_client ${BUILD_PACMAN_CLIENT})
if(vdpm_use_release_bundle OR CMAKE_SYSTEM_NAME STREQUAL "Windows")
    set(vdpm_build_package_client OFF)
endif()
set(vdpm_cmake_args
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX=${CMAKE_INSTALL_PREFIX}
    -DBUILD_VDPM_FRONTEND=ON
    -DBUILD_VDPM_CHANNEL=${vdpm_build_package_client}
    -DBUILD_VDPM_PACKAGE_CLIENT=${vdpm_build_package_client}
    -DVDPM_PACKAGE_CLIENT_INSTALL_PREFIX=${PACMAN_CLIENT_INSTALL_DIR}
    -DVDPM_DOWNLOAD_DIR=${DOWNLOAD_DIR}
    -DVDPM_OFFLINE=${OFFLINE}
    "-DCMAKE_C_FLAGS=${CMAKE_C_FLAGS}"
    "-DCMAKE_EXE_LINKER_FLAGS=${CMAKE_EXE_LINKER_FLAGS}")
if(VDPM_MESON_EXECUTABLE)
    list(APPEND vdpm_cmake_args
        -DMESON_EXECUTABLE=${VDPM_MESON_EXECUTABLE})
endif()
if(CMAKE_TOOLCHAIN_FILE)
    list(APPEND vdpm_cmake_args
        -DCMAKE_TOOLCHAIN_FILE=${toolchain_filepath})
endif()

if(vdpm_use_release_bundle)
    # Production SDK builds consume the exact published vdpm host product.
    # Source builds remain available as an explicit Unix development fallback.
    add_custom_target(vdpm
        COMMAND ${PROJECT_SOURCE_DIR}/scripts/install-vdpm-bundle.sh
            ${VDPM_BUNDLE}
            ${VDPM_BUNDLE_SHA256}
            ${CMAKE_INSTALL_PREFIX}
            ${host_native}
        VERBATIM)
else()
    ExternalProject_Add(vdpm
        GIT_REPOSITORY ${VDPM_REPOSITORY}
        GIT_TAG ${VDPM_TAG}
        ${GIT_SHALLOW_SUPPORT}
        CMAKE_ARGS ${vdpm_cmake_args}
        INSTALL_COMMAND ${CMAKE_COMMAND} --build <BINARY_DIR> --target install
        COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/include ${CMAKE_INSTALL_PREFIX}/bin/include
        COMMAND ${CMAKE_COMMAND} -E copy <SOURCE_DIR>/vitasdk-update ${CMAKE_INSTALL_PREFIX}/bin/
        ${UPDATE_DISCONNECTED_SUPPORT}
        )
endif()

# vdpm owns Pacman, its private dependencies and the channel helper. Keep this
# compatibility target while buildscripts callers migrate to the component
# boundary; the outer superbuild only waits for vdpm and audits the result.
if(BUILD_PACMAN_CLIENT)
    set(package_client_dependencies vdpm)
    set(package_client_audit_root ${PACMAN_CLIENT_INSTALL_DIR})
    if(vdpm_use_release_bundle)
        set(package_client_audit_root ${CMAKE_INSTALL_PREFIX})
    endif()
    add_custom_target(pacman-client-spike
        COMMAND ${CMAKE_COMMAND} -E env
            VITASDK=${package_client_audit_root}
            VITASDK_HOST_SYSTEM_NAME=${CMAKE_SYSTEM_NAME}
            ${PROJECT_SOURCE_DIR}/scripts/audit-host-deps.sh
        DEPENDS ${package_client_dependencies}
        VERBATIM)
    add_custom_target(package-client-configuration
        COMMAND ${CMAKE_COMMAND}
            -DOUTPUT=${CMAKE_INSTALL_PREFIX}/etc/pacman.conf
            -DHOST_ARCHITECTURE=${host_native}
            -P ${PROJECT_SOURCE_DIR}/cmake/WritePacmanConfig.cmake
        DEPENDS vdpm
        VERBATIM)
endif()

ExternalProject_Add(vita-makepkg
    GIT_REPOSITORY ${VITA_MAKEPKG_REPOSITORY}
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

set(version_info_file ${CMAKE_INSTALL_PREFIX}/version_info.txt)

# Merge the commit ids of the collected projects into a single file
add_custom_command(OUTPUT ${version_info_file}
    COMMAND ${CMAKE_COMMAND} -DINPUT_DIR=${CMAKE_BINARY_DIR} -DOUTPUT_FILE=${version_info_file}
    -P ${CMAKE_SOURCE_DIR}/cmake/create_version.cmake
    DEPENDS vita-headers vita-toolchain_${target_suffix} newlib pthread-embedded samples
    COMMENT "Creating version_info.txt"
    )

set(finalize_sdk_dependencies
    vita-toolchain_${target_suffix}
    binutils_${target_suffix}
    gdb_${target_suffix}
    vita-headers
    newlib
    pthread-embedded
    samples
    vdpm
    vita-makepkg
    gcc-final
    ${version_info_file})
if(BUILD_PACMAN_CLIENT)
    list(APPEND finalize_sdk_dependencies package-client-configuration)
endif()
# Finalize only after every component has installed into the SDK. This is the
# single barrier for cleanup, stripping, provenance and structural checks.
add_custom_target(finalize-sdk
    COMMAND ${CMAKE_COMMAND}
        -DHOST_SYSTEM_NAME=${CMAKE_HOST_SYSTEM_NAME}
        -DBINDIR=${CMAKE_INSTALL_PREFIX}/bin
        -P ${CMAKE_SOURCE_DIR}/cmake/strip_host_binaries.cmake
    COMMAND ${CMAKE_COMMAND}
        -DHOST_SYSTEM_NAME=${CMAKE_HOST_SYSTEM_NAME}
        -DBINDIR=${CMAKE_INSTALL_PREFIX}/${target_arch}/bin
        -P ${CMAKE_SOURCE_DIR}/cmake/strip_host_binaries.cmake
    COMMAND ${CMAKE_COMMAND}
        -DHOST_SYSTEM_NAME=${CMAKE_HOST_SYSTEM_NAME}
        -DBINDIR=${CMAKE_INSTALL_PREFIX}/lib/gcc/${target_arch}/${GCC_VERSION}
        -P ${CMAKE_SOURCE_DIR}/cmake/strip_host_binaries.cmake
    COMMAND ${CMAKE_COMMAND}
        -DOBJCOPY_COMMAND=${binutils_prefix}-objcopy
        "-DPATTERN_GLOB=${CMAKE_INSTALL_PREFIX}/${target_arch}/lib/*.[ao]"
        -P ${CMAKE_SOURCE_DIR}/cmake/strip_target_objects.cmake
    COMMAND ${CMAKE_COMMAND}
        -DOBJCOPY_COMMAND=${binutils_prefix}-objcopy
        "-DPATTERN_GLOB=${CMAKE_INSTALL_PREFIX}/lib/gcc/${target_arch}/${GCC_VERSION}/*[!d][!d][!l].[ao]"
        -P ${CMAKE_SOURCE_DIR}/cmake/strip_target_objects.cmake
    COMMAND ${CMAKE_COMMAND} -E remove_directory
        ${CMAKE_INSTALL_PREFIX}/share/man
    COMMAND ${CMAKE_COMMAND} -E remove_directory
        ${CMAKE_INSTALL_PREFIX}/share/info
    COMMAND ${CMAKE_COMMAND}
        "-DGLOB_PATTERN=${CMAKE_INSTALL_PREFIX}/*.la"
        -P ${CMAKE_SOURCE_DIR}/cmake/remove_files.cmake
    COMMAND ${CMAKE_COMMAND}
        -DSDK_DIR=${CMAKE_INSTALL_PREFIX}
        -DTARGET_TRIPLE=${target_arch}
        -DVERSION_FILE=${version_info_file}
        -P ${CMAKE_SOURCE_DIR}/cmake/ValidateSdk.cmake
    COMMAND ${CMAKE_COMMAND}
        -DSDK_DIR=${CMAKE_INSTALL_PREFIX}
        -DTARGET_TRIPLE=${target_arch}
        -P ${CMAKE_SOURCE_DIR}/cmake/ValidateStaticSdk.cmake
    COMMAND ${CMAKE_COMMAND} -E env
        VITASDK=${CMAKE_INSTALL_PREFIX}
        VITASDK_HOST_SYSTEM_NAME=${CMAKE_SYSTEM_NAME}
        VITASDK_OBJDUMP=${host_native}-objdump
        ${CMAKE_SOURCE_DIR}/scripts/audit-host-deps.sh
    DEPENDS ${finalize_sdk_dependencies}
    COMMENT "Finalizing and validating VitaSDK"
    VERBATIM
    )

add_custom_target(check-toolchain-contract
    COMMAND ${CMAKE_COMMAND} -E env
        VITASDK=${CMAKE_INSTALL_PREFIX}
        ${CMAKE_SOURCE_DIR}/tests/toolchain-contract/run.sh
    DEPENDS finalize-sdk
    VERBATIM
    )

add_custom_target(audit-host-dependencies
    COMMAND ${CMAKE_COMMAND} -E env
        VITASDK=${CMAKE_INSTALL_PREFIX}
        VITASDK_HOST_SYSTEM_NAME=${CMAKE_SYSTEM_NAME}
        VITASDK_OBJDUMP=${host_native}-objdump
        ${CMAKE_SOURCE_DIR}/scripts/audit-host-deps.sh
    DEPENDS finalize-sdk
    VERBATIM
    )

add_custom_target(check-static-policy
    COMMAND ${CMAKE_COMMAND}
        -P ${CMAKE_SOURCE_DIR}/tests/cmake/static-policy.cmake
    COMMAND ${CMAKE_COMMAND}
        -P ${CMAKE_SOURCE_DIR}/tests/cmake/static-sdk-validation.cmake
    VERBATIM
    )

add_custom_command(OUTPUT "vitasdk-${host_native}-${build_date}.tar.bz2"
    COMMAND ${CMAKE_COMMAND} -E tar "cfvj" "vitasdk-${host_native}-${build_date}.tar.bz2" "${CMAKE_INSTALL_PREFIX}"
    DEPENDS finalize-sdk
    COMMENT "Creating vitasdk-${host_native}-${build_date}.tar.bz2"
    )

# Create a sdk tarball
add_custom_target(tarball DEPENDS "vitasdk-${host_native}-${build_date}.tar.bz2")

if(BUILD_PACMAN_CLIENT)
    set(VITASDK_BOOTSTRAP_OUTPUT_DIR "${CMAKE_BINARY_DIR}/bootstraps" CACHE PATH
        "Output directory for verified VitaSDK bootstrap archives")
    set(bootstrap_archive
        "${VITASDK_BOOTSTRAP_OUTPUT_DIR}/vitasdk-bootstrap-${host_native}.tar.bz2")
    add_custom_command(OUTPUT ${bootstrap_archive}
        BYPRODUCTS ${bootstrap_archive}.sha256
        COMMAND ${CMAKE_COMMAND} -E make_directory ${VITASDK_BOOTSTRAP_OUTPUT_DIR}
        COMMAND ${CMAKE_COMMAND} -E rm -f
            ${bootstrap_archive} ${bootstrap_archive}.sha256
        COMMAND ${PROJECT_SOURCE_DIR}/scripts/create-bootstrap-archive.sh
            ${CMAKE_INSTALL_PREFIX}
            ${VITASDK_BOOTSTRAP_OUTPUT_DIR}
            ${host_native}
            ${VITASDK_SOURCE_DATE_EPOCH}
        DEPENDS finalize-sdk
            ${PROJECT_SOURCE_DIR}/scripts/create-bootstrap-archive.sh
        VERBATIM)
    add_custom_target(bootstrap-archive DEPENDS ${bootstrap_archive})
endif()

if(BUILD_PACMAN_CLIENT)
    set(VITASDK_PACKAGE_OUTPUT_DIR "${CMAKE_BINARY_DIR}/packages" CACHE PATH
        "Output directory for the vitasdk-core package")
    set(core_package
        "${VITASDK_PACKAGE_OUTPUT_DIR}/vitasdk-core-${VITASDK_PACKAGE_VERSION}-1-${host_native}.pkg.tar.xz")

    add_custom_command(OUTPUT ${core_package}
        COMMAND ${CMAKE_COMMAND} -E make_directory ${VITASDK_PACKAGE_OUTPUT_DIR}
        COMMAND ${CMAKE_COMMAND} -E rm -f ${core_package}
        COMMAND ${CMAKE_COMMAND} -E env
            SOURCE_DATE_EPOCH=${VITASDK_SOURCE_DATE_EPOCH}
            ${CMAKE_SOURCE_DIR}/scripts/create-core-package.sh
            ${CMAKE_INSTALL_PREFIX}
            ${VITASDK_PACKAGE_OUTPUT_DIR}
            ${host_native}
            ${VITASDK_PACKAGE_VERSION}
            ${VITASDK_SOURCE_REVISION}
        DEPENDS finalize-sdk
            ${CMAKE_SOURCE_DIR}/scripts/create-core-package.sh
            ${CMAKE_SOURCE_DIR}/scripts/validate-core-package.sh
        COMMENT "Creating ${core_package}"
        VERBATIM)

    add_custom_target(core-package DEPENDS ${core_package})
endif()
