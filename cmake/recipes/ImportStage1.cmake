#
# Copyright(c) 2016 codestation
# Distributed under the MIT License (http://opensource.org/licenses/MIT)
#

# Stage 2: import the target sysroot and SDK data from an unpacked stage-1
# native SDK (VITASDK_STAGE1_DIR) instead of rebuilding it.
#
# The targets defined here carry the same names as the ExternalProjects they
# replace (newlib, pthread-embedded, vita-headers, samples, gcc-complete) so
# that BuildGccFinal.cmake and FinalizeSdk.cmake keep their DEPENDS lists
# untouched. Each stage-1 payload is copied exactly once and every stub
# depends on that single copy step.
#
# What gcc-final still builds in stage 2: the host compiler binaries and the
# target runtime libraries that belong to the GCC version being built
# (libgcc, libstdc++, libgomp). Those are compiled with the *stage-1 native*
# arm-vita-eabi-gcc through CC_FOR_TARGET/GCC_FOR_TARGET, which is why
# toolchain_build_install_dir points at VITASDK_STAGE1_DIR.

include_guard(GLOBAL)

set(stage1_import_stamp ${CMAKE_BINARY_DIR}/stage1-import.stamp)

add_custom_command(OUTPUT ${stage1_import_stamp}
    # Target sysroot: newlib, pthread-embedded, vita-headers includes and
    # stub libraries, all already installed under ${target_arch} by stage 1.
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${VITASDK_STAGE1_DIR}/${target_arch}
        ${CMAKE_INSTALL_PREFIX}/${target_arch}
    # NID database consumed by vita-libs-gen and downstream tooling.
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${VITASDK_STAGE1_DIR}/share/vita-headers
        ${CMAKE_INSTALL_PREFIX}/share/vita-headers
    # Samples and the gcc python pretty-printers share this prefix.
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${VITASDK_STAGE1_DIR}/share/gcc-${target_arch}
        ${CMAKE_INSTALL_PREFIX}/share/gcc-${target_arch}
    COMMAND ${CMAKE_COMMAND} -E touch ${stage1_import_stamp}
    COMMENT "Importing stage-1 sysroot from ${VITASDK_STAGE1_DIR}"
    VERBATIM)

add_custom_target(stage1-import DEPENDS ${stage1_import_stamp})

# Stubs matching the native-build ExternalProject names. gcc-final and the
# finalize barrier depend on these by name.
foreach(stage1_stub newlib pthread-embedded vita-headers samples gcc-complete)
    add_custom_target(${stage1_stub})
    add_dependencies(${stage1_stub} stage1-import)
endforeach()

# Component provenance: stage 1 already merged the per-component commit ids
# into its version_info.txt. Reuse it verbatim instead of regenerating it
# from per-component files that only exist in the stage-1 build tree.
set(stage1_version_info ${VITASDK_STAGE1_DIR}/version_info.txt)
if(NOT EXISTS ${stage1_version_info})
    message(FATAL_ERROR "Stage-1 SDK has no version_info.txt; refusing to build an SDK without provenance")
endif()
