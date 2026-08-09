#
# Copyright(c) 2016 codestation
# Distributed under the MIT License (http://opensource.org/licenses/MIT)
#

# Build a complete gcc compiler to be able to compile the full gcc for the host when crosscompiling.
# Using gcc-base doesn't work since is missing some headers.
if(CMAKE_TOOLCHAIN_FILE)
    ExternalProject_add(gcc-complete
        DEPENDS newlib gmp_${build_suffix} mpfr_${build_suffix} mpc_${build_suffix} isl_${build_suffix} libelf_${build_suffix}
        URL ${GCC_URL}
        URL_HASH ${GCC_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        PATCH_COMMAND ${CMAKE_COMMAND}
            -DSOURCE_DIR=<SOURCE_DIR>
            "-DPATCH_SERIES=${gcc_patch_series_arg}"
            -P ${PROJECT_SOURCE_DIR}/cmake/ApplyPatches.cmake
        CONFIGURE_COMMAND ${compiler_flags} ${toolchain_tools}
        ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        # compile a native compiler so keep host == build
        --host=${build_native}
        --target=${target_arch}
        --prefix=${toolchain_build_install_dir}
        --libdir=${toolchain_build_install_dir}/lib
        --libexecdir=${toolchain_build_install_dir}/lib
        --with-sysroot=${toolchain_build_install_dir}/${target_arch}
        --with-gmp=${toolchain_build_depends_dir}
        --with-mpfr=${toolchain_build_depends_dir}
        --with-mpc=${toolchain_build_depends_dir}
        --with-isl=${toolchain_build_depends_dir}
        --with-libelf=${toolchain_build_depends_dir}
        ${common_gcc_configure_args}
        --enable-threads=posix
        --with-headers=yes
        --enable-libgomp
        "CFLAGS=${GCC_CFLAGS}"
        "CXXFLAGS=${GCC_CFLAGS}"
        BUILD_COMMAND ${toolchain_tools} ${wrapper_command} $(MAKE) INHIBIT_LIBC_CFLAGS="-DUSE_TM_CLONE_REGISTRY=0"
        INSTALL_COMMAND $(MAKE) install
        )
    # Add this target as dependency of the final gcc target
    set(GCC_DEPENDS gcc-complete)
else()
    # Just use gcc-base as the dependency of the final gcc target
    set(GCC_DEPENDS gcc-base)
endif()

ExternalProject_add(gcc-final
    DEPENDS gmp_${target_suffix} mpfr_${target_suffix} mpc_${target_suffix} isl_${target_suffix} libelf_${target_suffix}
    DEPENDS newlib ${GCC_DEPENDS} pthread-embedded
    URL ${GCC_URL}
    URL_HASH ${GCC_HASH}
    DOWNLOAD_DIR ${DOWNLOAD_DIR}
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    PATCH_COMMAND ${CMAKE_COMMAND}
        -DSOURCE_DIR=<SOURCE_DIR>
        "-DPATCH_SERIES=${gcc_patch_series_arg}"
        -P ${PROJECT_SOURCE_DIR}/cmake/ApplyPatches.cmake
    CONFIGURE_COMMAND ${compiler_flags} ${toolchain_tools} ${compiler_target_tools}
    ${wrapper_command} <SOURCE_DIR>/configure
    --build=${build_native}
    --host=${host_native}
    --target=${target_arch}
    --prefix=${CMAKE_INSTALL_PREFIX}
    --libdir=${CMAKE_INSTALL_PREFIX}/lib
    --libexecdir=${CMAKE_INSTALL_PREFIX}/lib
    --with-sysroot=${CMAKE_INSTALL_PREFIX}/${target_arch}
    --with-gmp=${toolchain_target_depends_dir}
    --with-mpfr=${toolchain_target_depends_dir}
    --with-mpc=${toolchain_target_depends_dir}
    --with-isl=${toolchain_target_depends_dir}
    --with-libelf=${toolchain_target_depends_dir}
    ${common_gcc_configure_args}
    --with-headers=yes
    --enable-threads=posix
    --enable-libgomp
    "CFLAGS=${GCC_CFLAGS}"
    "CXXFLAGS=${GCC_CFLAGS}"
    BUILD_COMMAND ${toolchain_tools} ${compiler_target_tools} ${wrapper_command}
    $(MAKE) INHIBIT_LIBC_CFLAGS="-DUSE_TM_CLONE_REGISTRY=0"
    INSTALL_COMMAND $(MAKE) install
    )
