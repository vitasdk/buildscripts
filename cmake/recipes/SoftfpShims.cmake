#
# Copyright(c) 2016 codestation
# Distributed under the MIT License (http://opensource.org/licenses/MIT)
#

# The softfp world calls the same hard-float Sce* stubs vita-headers just
# installed, but with float/double arguments and return values sitting in the
# wrong registers (AAPCS-base vs AAPCS-VFP). Splice the 23 shims from
# softfp-shim/ into the affected stub archives in place -- see PLAN-softfp.md,
# "Fase 1 - los 23 shims de serie" and scripts/patch-softfp-stub-archives.sh
# for why this is an archive rewrite and not a -lvita_softfp_shim added to
# LIB_SPEC.
#
# Its own file because it has to be included after the compiler that
# assembles the wrappers exists. It used to depend on the base compiler the
# staged pipeline stopped building, and the dangling name went unnoticed until
# the target was first asked for.

include_guard(GLOBAL)

if(VITASDK_FLOAT_ABI STREQUAL "softfp")
    add_custom_command(
        OUTPUT ${CMAKE_BINARY_DIR}/softfp-shim.stamp
        COMMAND ${PROJECT_SOURCE_DIR}/scripts/build-softfp-shim.sh
            ${binutils_prefix}-gcc ${binutils_prefix}-ar ${binutils_prefix}-objcopy
            ${PROJECT_SOURCE_DIR}/softfp-shim
            ${CMAKE_INSTALL_PREFIX}/${target_arch}/include
            ${CMAKE_INSTALL_PREFIX}/${target_arch}/lib
            ${toolchain_build_install_dir}/${target_arch}/lib
        COMMAND ${CMAKE_COMMAND} -E touch ${CMAKE_BINARY_DIR}/softfp-shim.stamp
        DEPENDS vita-headers ${gcc_final_barrier} binutils_${build_suffix}
        COMMENT "Splicing the softfp ABI shims into the stub archives"
        VERBATIM
        )
    add_custom_target(softfp-shim DEPENDS ${CMAKE_BINARY_DIR}/softfp-shim.stamp)
endif()
