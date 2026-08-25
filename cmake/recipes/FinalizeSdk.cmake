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
            -DHOST_ARCHITECTURE=${host_published}
            -P ${PROJECT_SOURCE_DIR}/cmake/WritePacmanConfig.cmake
        DEPENDS vdpm
        VERBATIM)
endif()

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
    ${gcc_final_barrier}
    ${version_info_file})
if(BUILD_PACMAN_CLIENT)
    list(APPEND finalize_sdk_dependencies package-client-configuration)
endif()

# Target objects are stripped where they are produced. In stage 2 they arrive
# already stripped from stage 1, and the objcopy that would do it belongs to
# the stage-1 host anyway -- unusable on a host that only imports the sysroot.
set(target_object_strip_commands)
if(NOT VITASDK_STAGE1_DIR)
    list(APPEND target_object_strip_commands
        COMMAND ${CMAKE_COMMAND}
            -DOBJCOPY_COMMAND=${binutils_prefix}-objcopy
            "-DPATTERN_GLOB=${CMAKE_INSTALL_PREFIX}/${target_arch}/lib/*.[ao]"
            -P ${CMAKE_SOURCE_DIR}/cmake/strip_target_objects.cmake
        COMMAND ${CMAKE_COMMAND}
            -DOBJCOPY_COMMAND=${binutils_prefix}-objcopy
            "-DPATTERN_GLOB=${CMAKE_INSTALL_PREFIX}/lib/gcc/${target_arch}/${GCC_VERSION}/*[!d][!d][!l].[ao]"
            -DSKIP_GCC_LTO_PLUGIN=ON
            -P ${CMAKE_SOURCE_DIR}/cmake/strip_target_objects.cmake)
endif()

# The audit reads the SDK's own binaries, so it needs an objdump that
# understands them. A cross build has the host-prefixed one in PATH; a native
# build may only have the plain name -- Alpine, for one, ships no
# aarch64-linux-musl-objdump. Prefer the prefixed name, fall back to the
# system's, and say so rather than failing at the last step of a long build.
find_program(VITASDK_HOST_OBJDUMP NAMES ${host_native}-objdump objdump)
if(NOT VITASDK_HOST_OBJDUMP)
    message(FATAL_ERROR
        "no objdump for the host dependency audit: looked for "
        "${host_native}-objdump and objdump")
endif()
message(STATUS "Host dependency audit reads with ${VITASDK_HOST_OBJDUMP}")

# Finalize only after every component has installed into the SDK. This is the
# single barrier for cleanup, stripping, provenance and structural checks.
add_custom_target(finalize-sdk
    COMMAND ${CMAKE_COMMAND}
        -DHOST_SYSTEM_NAME=${CMAKE_HOST_SYSTEM_NAME}
        -DCMAKE_STRIP=${CMAKE_STRIP}
        -DBINDIR=${CMAKE_INSTALL_PREFIX}/bin
        -P ${CMAKE_SOURCE_DIR}/cmake/strip_host_binaries.cmake
    COMMAND ${CMAKE_COMMAND}
        -DHOST_SYSTEM_NAME=${CMAKE_HOST_SYSTEM_NAME}
        -DCMAKE_STRIP=${CMAKE_STRIP}
        -DBINDIR=${CMAKE_INSTALL_PREFIX}/${target_arch}/bin
        -P ${CMAKE_SOURCE_DIR}/cmake/strip_host_binaries.cmake
    COMMAND ${CMAKE_COMMAND}
        -DHOST_SYSTEM_NAME=${CMAKE_HOST_SYSTEM_NAME}
        -DCMAKE_STRIP=${CMAKE_STRIP}
        -DBINDIR=${CMAKE_INSTALL_PREFIX}/lib/gcc/${target_arch}/${GCC_VERSION}
        -P ${CMAKE_SOURCE_DIR}/cmake/strip_host_binaries.cmake
    ${target_object_strip_commands}
    COMMAND ${CMAKE_COMMAND}
        -DSDK_DIR=${CMAKE_INSTALL_PREFIX}
        -DTARGET_TRIPLE=${target_arch}
        -DGCC_VERSION=${GCC_VERSION}
        -P ${CMAKE_SOURCE_DIR}/cmake/PublishBfdPlugins.cmake
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
        -DHOST_TRIPLE=${host_native}
        -DVERSION_FILE=${version_info_file}
        -P ${CMAKE_SOURCE_DIR}/cmake/ValidateSdk.cmake
    COMMAND ${CMAKE_COMMAND}
        -DSDK_DIR=${CMAKE_INSTALL_PREFIX}
        -DTARGET_TRIPLE=${target_arch}
        -P ${CMAKE_SOURCE_DIR}/cmake/ValidateStaticSdk.cmake
    COMMAND ${CMAKE_COMMAND} -E env
        VITASDK=${CMAKE_INSTALL_PREFIX}
        VITASDK_HOST_SYSTEM_NAME=${CMAKE_SYSTEM_NAME}
        VITASDK_OBJDUMP=${VITASDK_HOST_OBJDUMP}
        ${CMAKE_SOURCE_DIR}/scripts/audit-host-deps.sh
    DEPENDS ${finalize_sdk_dependencies}
    COMMENT "Finalizing and validating VitaSDK"
    VERBATIM
    )

# Empty when the host's binaries run here as they are. A cross whose output
# this machine can still execute -- x86_64 macOS on arm64, through Rosetta --
# sets it to the launcher that makes that true, so the contract runs against
# the SDK that was actually built rather than being skipped.
include(${CMAKE_CURRENT_LIST_DIR}/../HostRunner.cmake)

set(VITASDK_HOST_RUNNER "" CACHE STRING
    "Launcher prefix for running this host's binaries, if one is needed")
vitasdk_host_runner_command(vitasdk_host_runner_argv "${VITASDK_HOST_RUNNER}")

add_custom_target(check-toolchain-contract
    COMMAND ${CMAKE_COMMAND} -E env
        VITASDK=${CMAKE_INSTALL_PREFIX}
        ${vitasdk_host_runner_argv}
        ${CMAKE_SOURCE_DIR}/tests/toolchain-contract/run.sh
    DEPENDS finalize-sdk
    VERBATIM
    )

add_custom_target(audit-host-dependencies
    COMMAND ${CMAKE_COMMAND} -E env
        VITASDK=${CMAKE_INSTALL_PREFIX}
        VITASDK_HOST_SYSTEM_NAME=${CMAKE_SYSTEM_NAME}
        VITASDK_OBJDUMP=${VITASDK_HOST_OBJDUMP}
        ${CMAKE_SOURCE_DIR}/scripts/audit-host-deps.sh
    DEPENDS finalize-sdk
    VERBATIM
    )

add_custom_target(check-sdk-partition
    COMMAND ${CMAKE_COMMAND}
        -P ${CMAKE_SOURCE_DIR}/tests/cmake/sysroot-manifest.cmake
    COMMAND ${CMAKE_COMMAND}
        -P ${CMAKE_SOURCE_DIR}/tests/cmake/host-binary-format.cmake
    VERBATIM)

add_custom_target(check-static-policy
    COMMAND ${CMAKE_COMMAND}
        -P ${CMAKE_SOURCE_DIR}/tests/cmake/static-policy.cmake
    COMMAND ${CMAKE_COMMAND}
        -P ${CMAKE_SOURCE_DIR}/tests/cmake/static-sdk-validation.cmake
    VERBATIM
    )

add_custom_command(OUTPUT "vitasdk-${host_published}-${build_date}.tar.bz2"
    COMMAND ${CMAKE_COMMAND} -E tar "cfvj" "vitasdk-${host_published}-${build_date}.tar.bz2" "${CMAKE_INSTALL_PREFIX}"
    DEPENDS finalize-sdk
    COMMENT "Creating vitasdk-${host_published}-${build_date}.tar.bz2"
    )

# Create a sdk tarball
add_custom_target(tarball DEPENDS "vitasdk-${host_published}-${build_date}.tar.bz2")

if(BUILD_PACMAN_CLIENT)
    set(VITASDK_BOOTSTRAP_OUTPUT_DIR "${CMAKE_BINARY_DIR}/bootstraps" CACHE PATH
        "Output directory for verified VitaSDK bootstrap archives")
    set(bootstrap_archive
        "${VITASDK_BOOTSTRAP_OUTPUT_DIR}/vitasdk-bootstrap-${host_published}.tar.bz2")
    add_custom_command(OUTPUT ${bootstrap_archive}
        BYPRODUCTS ${bootstrap_archive}.sha256
        COMMAND ${CMAKE_COMMAND} -E make_directory ${VITASDK_BOOTSTRAP_OUTPUT_DIR}
        COMMAND ${CMAKE_COMMAND} -E rm -f
            ${bootstrap_archive} ${bootstrap_archive}.sha256
        COMMAND ${PROJECT_SOURCE_DIR}/scripts/create-bootstrap-archive.sh
            ${CMAKE_INSTALL_PREFIX}
            ${VITASDK_BOOTSTRAP_OUTPUT_DIR}
            ${host_published}
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
        "${VITASDK_PACKAGE_OUTPUT_DIR}/vitasdk-core-${VITASDK_PACKAGE_VERSION}-1-${host_published}.pkg.tar.xz")

    # A core release is two packages: the toolchain, and the client that
    # installs it. Both are outputs, and both have to be gone before a rerun.
    file(GLOB stale_client_packages
        "${VITASDK_PACKAGE_OUTPUT_DIR}/vdpm-*-1-${host_published}.pkg.tar.xz")

    add_custom_command(OUTPUT ${core_package}
        COMMAND ${CMAKE_COMMAND} -E make_directory ${VITASDK_PACKAGE_OUTPUT_DIR}
        COMMAND ${CMAKE_COMMAND} -E rm -f ${core_package} ${stale_client_packages}
        COMMAND ${CMAKE_COMMAND} -E env
            SOURCE_DATE_EPOCH=${VITASDK_SOURCE_DATE_EPOCH}
            ${CMAKE_SOURCE_DIR}/scripts/create-core-package.sh
            ${CMAKE_INSTALL_PREFIX}
            ${VITASDK_PACKAGE_OUTPUT_DIR}
            ${host_published}
            ${VITASDK_PACKAGE_VERSION}
            ${VITASDK_SOURCE_REVISION}
        DEPENDS finalize-sdk
            ${CMAKE_SOURCE_DIR}/scripts/create-core-package.sh
            ${CMAKE_SOURCE_DIR}/scripts/validate-core-package.sh
        COMMENT "Creating ${core_package}"
        VERBATIM)

    add_custom_target(core-package DEPENDS ${core_package})
endif()
