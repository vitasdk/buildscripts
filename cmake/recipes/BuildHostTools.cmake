#
# Copyright(c) 2016 codestation
# Distributed under the MIT License (http://opensource.org/licenses/MIT)
#

# vdpm and vita-makepkg are host tools: compiled with (or, for vita-makepkg,
# just copied for) the host this SDK targets, never the arm-vita-eabi target
# sysroot. That means they always need building here, in both worlds this
# file is included from -- unlike vita-headers/newlib/pthread-embedded/
# samples, a stage-2 build cannot import them from stage 1's sysroot tarball,
# because stage 1's vdpm/vita-makepkg were built for stage 1's own host, not
# this one.

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
            ${host_published}
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

ExternalProject_Add(vita-makepkg
    GIT_REPOSITORY ${VITA_MAKEPKG_REPOSITORY}
    GIT_TAG ${VITA_MAKEPKG_TAG}
    BUILD_IN_SOURCE 1
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ""
    INSTALL_COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_INSTALL_PREFIX}/bin/
    COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/libmakepkg ${CMAKE_INSTALL_PREFIX}/bin/libmakepkg
    COMMAND ${CMAKE_COMMAND} -E copy <SOURCE_DIR>/vita-makepkg ${CMAKE_INSTALL_PREFIX}/bin/
    COMMAND ${CMAKE_COMMAND}
        -DINPUT=<SOURCE_DIR>/makepkg.conf.sample
        -DOUTPUT=${CMAKE_INSTALL_PREFIX}/bin/makepkg.conf
        -DWORLD_ARCH=${world_arch}
        -P ${PROJECT_SOURCE_DIR}/cmake/WriteMakepkgConf.cmake
    ${UPDATE_DISCONNECTED_SUPPORT}
    )
