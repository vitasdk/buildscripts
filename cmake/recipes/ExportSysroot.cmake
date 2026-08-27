#
# Copyright(c) 2016 codestation
# Distributed under the MIT License (http://opensource.org/licenses/MIT)
#

# Producer mode (VITASDK_TARGET_ONLY): the build stops once every target
# artifact exists and ships those, and only those. No gdb, no package tools,
# no SDK validation, no complete tarball -- this build is not an SDK for
# anyone, it is the target half every host will import.
#
# The host binaries it did have to build (binutils, vita-libs-gen and the
# compiler that produced the target libraries) stay behind in the build
# prefix: cmake/SysrootManifest.cmake decides what leaves.

include_guard(GLOBAL)

# The tarball is created from inside this directory so it holds a single
# vitasdk/ root and no build paths. WORKING_DIRECTORY does not create it, and
# a directory that does not exist yet fails the whole command.
set(sysroot_root ${CMAKE_BINARY_DIR}/sysroot)
file(MAKE_DIRECTORY ${sysroot_root})
set(sysroot_staging ${sysroot_root}/vitasdk)
set(sysroot_tarball "vitasdk-sysroot-${build_date}.tar.bz2")

add_custom_target(sysroot
    # Target objects are stripped where they are produced; every consumer
    # imports them as they are.
    COMMAND ${CMAKE_COMMAND}
        -DOBJCOPY_COMMAND=${binutils_prefix}-objcopy
        "-DPATTERN_GLOB=${CMAKE_INSTALL_PREFIX}/${target_arch}/lib/*.[ao]"
        -P ${CMAKE_SOURCE_DIR}/cmake/strip_target_objects.cmake
    COMMAND ${CMAKE_COMMAND}
        -DOBJCOPY_COMMAND=${binutils_prefix}-objcopy
        "-DPATTERN_GLOB=${CMAKE_INSTALL_PREFIX}/lib/gcc/${target_arch}/${GCC_VERSION}/*[!d][!d][!l].[ao]"
        -DSKIP_GCC_LTO_PLUGIN=ON
        -P ${CMAKE_SOURCE_DIR}/cmake/strip_target_objects.cmake
    COMMAND ${CMAKE_COMMAND} -E rm -rf ${sysroot_staging}
    COMMAND ${CMAKE_COMMAND}
        -DSOURCE=${CMAKE_INSTALL_PREFIX}
        -DDESTINATION=${sysroot_staging}
        -DTARGET_TRIPLE=${target_arch}
        -DGCC_VERSION=${GCC_VERSION}
        -P ${CMAKE_SOURCE_DIR}/cmake/CopySysroot.cmake
    COMMAND ${CMAKE_COMMAND} -E tar "cfj" ${CMAKE_BINARY_DIR}/${sysroot_tarball} vitasdk
    WORKING_DIRECTORY ${sysroot_root}
    DEPENDS ${target_half_dependencies}
    COMMENT "Exporting the target half to ${sysroot_tarball}"
    VERBATIM
    )
