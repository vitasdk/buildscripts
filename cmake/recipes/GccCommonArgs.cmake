#
# Copyright(c) 2016 codestation
# Distributed under the MIT License (http://opensource.org/licenses/MIT)
#

# GCC patch series and configure arguments shared by gcc-base, gcc-complete
# and gcc-final. Split out so stage-2 builds (which never build gcc-base) can
# still configure gcc-final.
include_guard(GLOBAL)

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
    --enable-tls
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
    --with-float=${VITASDK_FLOAT_ABI}
    --with-mode=thumb
    "--with-pkgversion=${pkgversion}"
    )

if("${CMAKE_CXX_COMPILER_ID}" STREQUAL "GNU")
    list(APPEND common_gcc_configure_args
        "--with-host-libstdcxx=-static-libgcc -static-libstdc++ -lm")
endif()

