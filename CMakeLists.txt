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

# Modular recipes
include(cmake/recipes/BuildGccBase.cmake)
include(cmake/recipes/BuildSdkComponents.cmake)
include(cmake/recipes/BuildGccFinal.cmake)
include(cmake/recipes/FinalizeSdk.cmake)
