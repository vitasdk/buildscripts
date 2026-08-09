#
# Copyright(c) 2016 codestation
# Distributed under the MIT License (http://opensource.org/licenses/MIT)
#

ExternalProject_add(vita-headers
    DEPENDS binutils_${build_suffix} vita-toolchain_${build_suffix}
    GIT_REPOSITORY ${HEADERS_REPOSITORY}
    GIT_TAG ${HEADERS_TAG}
    ${GIT_SHALLOW_SUPPORT}
    CONFIGURE_COMMAND ${vita_libs_gen_command}-2 -yml=<SOURCE_DIR>/db -output=<BINARY_DIR>
    BUILD_COMMAND ARCH=${binutils_prefix} make
    # Copy the generated .a files to the install directory
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
