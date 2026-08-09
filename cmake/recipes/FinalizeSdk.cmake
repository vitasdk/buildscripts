#
# Copyright(c) 2016 codestation
# Distributed under the MIT License (http://opensource.org/licenses/MIT)
#

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
        -DSKIP_GCC_LTO_PLUGIN=ON
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
        -DHOST_SYSTEM_NAME=${CMAKE_SYSTEM_NAME}
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
