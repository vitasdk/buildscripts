#
# Copyright(c) 2016 codestation
# Distributed under the MIT License (http://opensource.org/licenses/MIT)
#

set(GCC_CFLAGS)
set(gcc_patch_series
    "${PROJECT_SOURCE_DIR}/patches/gcc/0001-vita-target.patch|1"
    "${PROJECT_SOURCE_DIR}/patches/gcc/0002-vita-driver.patch|1"
    "${PROJECT_SOURCE_DIR}/patches/gcc/0003-libgomp-vita.patch|1"
    "${PROJECT_SOURCE_DIR}/patches/gcc/0004-host-compat.patch|1")
list(JOIN gcc_patch_series "^" gcc_patch_series_arg)
if("${CMAKE_CXX_COMPILER_ID}" MATCHES "Clang" AND ${CMAKE_SYSTEM_NAME} STREQUAL "Darwin")
    # GCC on OSX (Clang in diguise) needs more bracket nesting depth to compile gcc
    set(GCC_CFLAGS "${GCC_CFLAGS} -fbracket-depth=512")
endif()

# Common gcc configure options
set(common_gcc_configure_args
    --with-python-dir=share/gcc-${target_arch}
    --enable-languages=c,c++
    --disable-decimal-float
    # libcc1 only implements GDB's optional "compile" command and installs
    # host shared objects that would make the SDK depend on the build host's
    # C++ runtime. It is not part of the Vita compiler contract.
    --disable-libcc1
    --disable-libffi
    --disable-libmudflap
    --disable-libquadmath
    --disable-libssp
    --disable-libstdcxx-pch
    --disable-nls
    --disable-shared
    --disable-tls
    --with-gnu-as
    --with-gnu-ld
    --with-newlib
    # Do not auto-detect the runner's shared zstd. Optional zstd compression
    # is outside the toolchain contract and would make the SDK non-relocatable.
    --without-zstd
    --disable-multilib
    --with-arch=armv7-a
    --with-tune=cortex-a9
    --with-fpu=neon
    --with-float=hard
    --with-mode=thumb
    "--with-pkgversion=${pkgversion}"
    )

if("${CMAKE_CXX_COMPILER_ID}" STREQUAL "GNU")
    list(APPEND common_gcc_configure_args
        "--with-host-libstdcxx=-static-libgcc -static-libstdc++ -lm")
endif()

# Build a basic gcc compiler, needed to compile newlib
ExternalProject_add(gcc-base
    DEPENDS gmp_${build_suffix} mpfr_${build_suffix} mpc_${build_suffix} isl_${build_suffix} libelf_${build_suffix}
    URL ${GCC_URL}
    URL_HASH ${GCC_HASH}
    DOWNLOAD_DIR ${DOWNLOAD_DIR}
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    PATCH_COMMAND ${CMAKE_COMMAND}
        -DSOURCE_DIR=<SOURCE_DIR>
        "-DPATCH_SERIES=${gcc_patch_series_arg}"
        -P ${PROJECT_SOURCE_DIR}/cmake/ApplyPatches.cmake
    CONFIGURE_COMMAND ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
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
    --disable-threads
    --without-headers
    --disable-libgomp
    "CFLAGS=${GCC_CFLAGS}"
    "CXXFLAGS=${GCC_CFLAGS}"
    BUILD_COMMAND $(MAKE) all-gcc
    INSTALL_COMMAND $(MAKE) install-gcc
    )
