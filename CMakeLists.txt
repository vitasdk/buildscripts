#
# Copyright(c) 2016 codestation
# Distributed under the MIT License (http://opensource.org/licenses/MIT)
#

cmake_minimum_required(VERSION 3.16)

project(vitasdk)

# ccache. This is a superbuild: it compiles nothing of its own, so a launcher
# set here reaches no compiler at all. It has to be forwarded to the
# sub-projects CMake configures. The heavy sub-projects (gcc, binutils, gdb,
# newlib) are autotools and honour no CMake variable whatsoever -- they pick up
# ccache only through a shim directory in PATH, which is what CI does.
find_program(CCACHE_PROGRAM ccache)
set(compiler_launcher_args)
if(CCACHE_PROGRAM)
    message(STATUS "ccache: ${CCACHE_PROGRAM}")
    list(APPEND compiler_launcher_args
        -DCMAKE_C_COMPILER_LAUNCHER=${CCACHE_PROGRAM}
        -DCMAKE_CXX_COMPILER_LAUNCHER=${CCACHE_PROGRAM})
endif()

include(cmake/Components.cmake)
include(cmake/StaticPolicy.cmake)

# Location to save the downloaded tarballs. Can be overriden from command line.
set(DOWNLOAD_DIR ${CMAKE_BINARY_DIR}/downloads CACHE PATH "Default download path for tarballs")

# Staged builds
# =============
# Stage 1 (native, Linux x86_64 in CI): builds everything that is target code
# -- the sysroot, newlib, pthread-embedded, the stubs, libgcc and the target
# runtimes -- with a native arm-vita-eabi compiler of its own.
# Stage 2 (every other host, cross or native): point VITASDK_STAGE1_DIR at an
# unpacked stage-1 SDK. The target half is imported, and the host half (the
# compiler proper, binutils, gdb, vita-toolchain, the package tools) is the
# only thing built. Target code is therefore compiled exactly once for the
# whole matrix, and no host but stage 1 needs a native arm-vita-eabi compiler.
# Native builds with no stage-1 dir keep working exactly as before; staging is
# an optimization, not a requirement.
set(VITASDK_STAGE1_DIR "" CACHE PATH
    "Unpacked stage-1 SDK whose target half is imported instead of rebuilt")

# Producer mode: build the target half and nothing else. What it emits is not
# an SDK for any host -- it is the input every host imports.
option(VITASDK_TARGET_ONLY
    "Build only the target half and export it as a sysroot tarball" OFF)

if(VITASDK_TARGET_ONLY AND VITASDK_STAGE1_DIR)
    message(FATAL_ERROR
        "VITASDK_TARGET_ONLY produces the target half and VITASDK_STAGE1_DIR "
        "consumes one; a build is one or the other.")
endif()
if(VITASDK_TARGET_ONLY AND CMAKE_TOOLCHAIN_FILE)
    message(FATAL_ERROR
        "VITASDK_TARGET_ONLY builds target code, which is host independent "
        "and native by definition; a toolchain file has nothing to cross.")
endif()

if(VITASDK_STAGE1_DIR)
    get_filename_component(VITASDK_STAGE1_DIR "${VITASDK_STAGE1_DIR}" ABSOLUTE)
    # What stage 2 consumes is target code, not the stage-1 host binaries, so
    # this checks for the payload and not for a compiler that would be useless
    # on a host of a different kind anyway.
    if(NOT EXISTS "${VITASDK_STAGE1_DIR}/arm-vita-eabi/lib/libc.a")
        message(FATAL_ERROR "VITASDK_STAGE1_DIR='${VITASDK_STAGE1_DIR}' has no target sysroot (missing arm-vita-eabi/lib/libc.a)")
    endif()
    if(NOT EXISTS "${VITASDK_STAGE1_DIR}/lib/gcc/arm-vita-eabi/${GCC_VERSION}/libgcc.a")
        message(FATAL_ERROR "VITASDK_STAGE1_DIR='${VITASDK_STAGE1_DIR}' carries no libgcc for gcc ${GCC_VERSION}; it was built from a different gcc")
    endif()
    message(STATUS "Stage 2 build: importing the target half from ${VITASDK_STAGE1_DIR}")
endif()

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
# Prepended to the configure of every project whose programs libtool links.
vitasdk_get_libtool_static_flag("${CMAKE_SYSTEM_NAME}" host_libtool_static_flag)
set(libtool_static_env)
if(host_libtool_static_flag)
    set(libtool_static_env "LDFLAGS=${host_libtool_static_flag}")
endif()

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

# Host dependencies recipe (toolchain_deps function)
include(cmake/recipes/BuildHostDependencies.cmake)

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
    # Build the host vita-toolchain, binutils and gcc-final dependencies
    toolchain_deps("${toolchain_target_depends_dir}" "${CMAKE_INSTALL_PREFIX}" "${host_suffix}" "${toolchain_filepath}")
else()
    set(target_suffix ${build_suffix})
    # Path of the build dependencies for gcc-final
    set(toolchain_target_depends_dir "${CMAKE_BINARY_DIR}/deps_${target_suffix}")
endif()

if(VITASDK_STAGE1_DIR AND CMAKE_TOOLCHAIN_FILE)
    # Cross stage 2: nothing here compiles target code, so the throwaway
    # native toolchain that feeds *_FOR_TARGET is not built at all. The
    # variables still name the stage-1 tree for the recipes that interpolate
    # them; no build step runs those binaries.
    #
    # A native stage 2 takes the branch below instead: there the build-suffix
    # toolchain is also the SDK's own binutils, gdb and vita-toolchain, which
    # every host has to build for itself.
    set(toolchain_build_install_dir ${VITASDK_STAGE1_DIR})
    set(toolchain_build_depends_dir ${CMAKE_BINARY_DIR}/deps_${build_suffix})
else()
    # Native toolchain install dir (used to build the real toolchain)
    set(toolchain_build_install_dir ${CMAKE_BINARY_DIR}/toolchain_${build_suffix})
    # Native toolchain dependencies dir
    set(toolchain_build_depends_dir ${CMAKE_BINARY_DIR}/deps_${build_suffix})
    # Build the native vita-toolchain, gcc dependencies and binutils
    toolchain_deps("${toolchain_build_depends_dir}" "${toolchain_build_install_dir}" "${build_suffix}")
endif()

option(BUILD_PACMAN_CLIENT "Build the package client provided by vdpm" OFF)
set(PACMAN_CLIENT_INSTALL_DIR "${CMAKE_INSTALL_PREFIX}"
    CACHE PATH "Install directory for the vdpm package client")
set(VDPM_BUNDLE "" CACHE FILEPATH
    "Verified vdpm host component bundle incorporated into the SDK")
set(VDPM_BUNDLE_SHA256 "" CACHE STRING
    "SHA-256 of VDPM_BUNDLE")
set(VDPM_MESON_EXECUTABLE "" CACHE FILEPATH
    "Optional Meson executable forwarded to the vdpm component")

# The compiler and binutils that build target code live in the SDK prefix:
# there is one of each now, and it is the one being shipped. The throwaway
# toolchain directory that used to hold a second copy is gone with gcc-base.
set(vita_libs_gen_command "${CMAKE_INSTALL_PREFIX}/bin/vita-libs-gen")
set(binutils_prefix "${CMAKE_INSTALL_PREFIX}/bin/${target_arch}")

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

# Modular recipes
if(VITASDK_STAGE1_DIR)
    # Stage 2: gcc-base is not built (common gcc configure args still needed
    # by gcc-final) and the sysroot components are imported from stage 1.
    include(cmake/recipes/GccCommonArgs.cmake)
    include(cmake/recipes/ImportStage1.cmake)
else()
    include(cmake/recipes/GccCommonArgs.cmake)
    include(cmake/recipes/BuildSdkComponents.cmake)
endif()
# vdpm/vita-makepkg are host tools, rebuilt per host in both stages -- stage 2
# cannot import them from stage 1's sysroot the way it does the target pieces
# above, since stage 1's copies were built for stage 1's own host. A producer
# ships no host binaries at all, so it builds neither.
if(NOT VITASDK_TARGET_ONLY)
    include(cmake/recipes/BuildHostTools.cmake)
endif()
include(cmake/recipes/BuildGccFinal.cmake)
include(cmake/recipes/Provenance.cmake)
if(VITASDK_TARGET_ONLY)
    include(cmake/recipes/ExportSysroot.cmake)
else()
    include(cmake/recipes/FinalizeSdk.cmake)
endif()
