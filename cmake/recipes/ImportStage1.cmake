#
# Copyright(c) 2016 codestation
# Distributed under the MIT License (http://opensource.org/licenses/MIT)
#

# Stage 2: import the target sysroot and SDK data from an unpacked stage-1
# native SDK (VITASDK_STAGE1_DIR) instead of rebuilding it.
#
# The targets defined here carry the same names as the ExternalProjects they
# replace (newlib, pthread-embedded, vita-headers, samples) so that
# FinalizeSdk.cmake keeps its DEPENDS list untouched. Each stage-1 payload is
# copied exactly once and every stub depends on that single copy step.
#
# What gcc-final builds in stage 2: the compiler proper and nothing else
# (all-gcc). Every target artifact -- newlib, the stubs, libstdc++, libgomp,
# libgcc and the crt objects -- comes from stage 1, so target code is compiled
# exactly once for the whole matrix and no host needs a native arm-vita-eabi
# compiler of its own. cmake/SysrootManifest.cmake holds the partition.

include_guard(GLOBAL)

set(stage1_import_stamp ${CMAKE_BINARY_DIR}/stage1-import.stamp)

add_custom_command(OUTPUT ${stage1_import_stamp}
    COMMAND ${CMAKE_COMMAND}
        -DSTAGE1_DIR=${VITASDK_STAGE1_DIR}
        -DPREFIX=${CMAKE_INSTALL_PREFIX}
        -DTARGET_TRIPLE=${target_arch}
        -DGCC_VERSION=${GCC_VERSION}
        -P ${PROJECT_SOURCE_DIR}/cmake/ImportSysroot.cmake
    COMMAND ${CMAKE_COMMAND} -E touch ${stage1_import_stamp}
    COMMENT "Importing stage-1 sysroot from ${VITASDK_STAGE1_DIR}"
    VERBATIM)

add_custom_target(stage1-import DEPENDS ${stage1_import_stamp})

# Stubs matching the native-build ExternalProject names. gcc-final and the
# finalize barrier depend on these by name.
foreach(stage1_stub newlib pthread-embedded vita-headers samples)
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
