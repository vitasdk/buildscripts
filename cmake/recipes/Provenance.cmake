#
# Copyright(c) 2016 codestation
# Distributed under the MIT License (http://opensource.org/licenses/MIT)
#

# Provenance: the commit ids every component was built from. It belongs to the
# target half -- a consumer imports it rather than regenerating it, because
# the components it names were built somewhere else.

include_guard(GLOBAL)

set(version_info_file ${CMAKE_INSTALL_PREFIX}/version_info.txt)

# Merge the commit ids of the collected projects into a single file
if(VITASDK_STAGE1_DIR)
    # Stage 2: the sysroot components come from stage 1, so their provenance
    # does too. Only the buildscripts revision differs and is already
    # recorded through VITASDK_SOURCE_REVISION in the package metadata.
    add_custom_command(OUTPUT ${version_info_file}
        COMMAND ${CMAKE_COMMAND} -E copy
            ${VITASDK_STAGE1_DIR}/version_info.txt ${version_info_file}
        DEPENDS vita-headers vita-toolchain_${target_suffix} newlib pthread-embedded samples
        COMMENT "Importing version_info.txt from stage 1"
        )
else()
    add_custom_command(OUTPUT ${version_info_file}
        COMMAND ${CMAKE_COMMAND} -DINPUT_DIR=${CMAKE_BINARY_DIR} -DOUTPUT_FILE=${version_info_file}
        -DWORLD_ARCH=${world_arch} -DVITASDK_FLOAT_ABI=${VITASDK_FLOAT_ABI}
        -P ${CMAKE_SOURCE_DIR}/cmake/create_version.cmake
        DEPENDS vita-headers vita-toolchain_${target_suffix} newlib pthread-embedded samples
        COMMENT "Creating version_info.txt"
        )
endif()
