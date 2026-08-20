#
# Copyright(c) 2016 codestation
# Distributed under the MIT License (http://opensource.org/licenses/MIT)
#

# The compiler, in one of two shapes.
#
# Producer (no stage-1 SDK): a single gcc build tree produces both the
# compiler and every target library. It is split into steps so newlib and
# pthread-embedded can be built with the compiler in the middle of it:
#
#   configure -> all-gcc -> install-gcc -> (newlib, stubs, pthread) ->
#   libgcc, libstdc++, libgomp -> install
#
# The second gcc build this replaces existed only because a compiler
# configured --without-headers cannot build libstdc++. One tree, one
# configure, one cc1.
#
# Consumer (VITASDK_STAGE1_DIR): every target artifact is imported, so gcc
# builds the compiler proper and stops. Nothing here compiles target code,
# which is what lets a host with no runnable arm-vita-eabi compiler take part.

if(CMAKE_TOOLCHAIN_FILE AND NOT VITASDK_STAGE1_DIR)
    message(FATAL_ERROR
        "Cross building needs a stage-1 SDK: target code is compiled once, "
        "natively, and imported by every other host. Build one with a plain "
        "native build and pass VITASDK_STAGE1_DIR=<its prefix>.")
endif()

if(VITASDK_STAGE1_DIR)
    set(gcc_final_depends stage1-import)
    set(gcc_final_build_targets all-gcc all-lto-plugin)
    set(gcc_final_install_targets install-gcc install-lto-plugin)
    # The barrier every consumer of a finished compiler waits on.
    set(gcc_final_barrier gcc-final)
else()
    set(gcc_final_depends
        binutils_${build_suffix} vita-toolchain_${build_suffix})
    set(gcc_final_build_targets all-gcc all-lto-plugin)
    set(gcc_final_install_targets install-gcc install-lto-plugin)
    set(gcc_final_barrier gcc-final-target-libs)
endif()

ExternalProject_add(gcc-final
    DEPENDS gmp_${target_suffix} mpfr_${target_suffix} mpc_${target_suffix} isl_${target_suffix} libelf_${target_suffix}
    DEPENDS ${gcc_final_depends}
    URL ${GCC_URL}
    URL_HASH ${GCC_HASH}
    DOWNLOAD_DIR ${DOWNLOAD_DIR}
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    PATCH_COMMAND ${CMAKE_COMMAND}
        -DSOURCE_DIR=<SOURCE_DIR>
        "-DPATCH_SERIES=${gcc_patch_series_arg}"
        -P ${PROJECT_SOURCE_DIR}/cmake/ApplyPatches.cmake
    # CC_FOR_TARGET and friends are deliberately absent: with gcc in the same
    # tree the generated makefiles build target libraries with the in-tree
    # xgcc and ignore them. The headers are found through FLAGS_FOR_TARGET,
    # which carries -isystem <prefix>/<triple>/include and is evaluated when
    # the library is compiled, not when gcc is configured.
    CONFIGURE_COMMAND ${compiler_flags} ${toolchain_tools}
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
    # Never a bare make here: it would reach for the target libraries against
    # a sysroot that has no libc yet.
    BUILD_COMMAND ${toolchain_tools} ${wrapper_command}
    $(MAKE) ${gcc_final_build_targets} INHIBIT_LIBC_CFLAGS="-DUSE_TM_CLONE_REGISTRY=0"
    INSTALL_COMMAND $(MAKE) ${gcc_final_install_targets}
    )

if(NOT VITASDK_STAGE1_DIR)
    # The rest of the same tree, once the sysroot has a libc and a pthread.h.
    #
    # INHIBIT_LIBC_CFLAGS is not decoration. gcc's configure looks for
    # <sysroot>/usr/include/stdio.h to decide whether a libc exists; our
    # headers live in <sysroot>/include, so that file never exists and gcc
    # records inhibit_libc=true. Overriding the variable on the command line
    # is what discards the resulting -Dinhibit_libc and yields a complete
    # libgcc. Without it the build still succeeds -- with a crippled one.
    ExternalProject_Add_Step(gcc-final target-libs
        COMMAND ${toolchain_tools} ${wrapper_command}
            $(MAKE) INHIBIT_LIBC_CFLAGS="-DUSE_TM_CLONE_REGISTRY=0"
        COMMAND $(MAKE) install
        WORKING_DIRECTORY <BINARY_DIR>
        COMMENT "Building the target libraries (libgcc, libstdc++, libgomp)"
        DEPENDEES install
        # Without this the step joins the gcc-final target's own chain and
        # runs right after install-gcc, before newlib exists.
        EXCLUDE_FROM_MAIN TRUE
        )
    ExternalProject_Add_StepTargets(gcc-final install target-libs)

    # The staged sequence, wired here because this is where both halves are
    # visible. ExternalProject's own DEPENDS cannot express it: it resolves
    # names to other external projects and their stamp files, and these are
    # step targets.
    add_dependencies(newlib gcc-final-install)
    add_dependencies(pthread-embedded gcc-final-install)
    # libgcc compiles emutls.c, whose gthr-posix.h includes <pthread.h>:
    # pthread-embedded has to be installed before any of this runs.
    add_dependencies(gcc-final-target-libs newlib pthread-embedded)
endif()
