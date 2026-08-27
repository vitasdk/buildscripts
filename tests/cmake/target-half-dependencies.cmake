# The export and the finalize barrier wait for the same target half.
#
# They are mutually exclusive -- a producer exports a sysroot for stage 2, any
# other build finalizes its own -- so a piece added to one and forgotten in the
# other is invisible until something reads the result. The softfp shims were
# spliced by finalize-sdk and not by the export, so a staged build handed
# stage 2 a sysroot whose stub archives had never been patched, and the ABI
# contract test found it two jobs later.

cmake_minimum_required(VERSION 3.16)

get_filename_component(repository_root "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
set(failures 0)

function(expect_contains path needle description)
    file(READ "${repository_root}/${path}" contents)
    string(FIND "${contents}" "${needle}" position)
    if(position EQUAL -1)
        message(SEND_ERROR "FAIL: ${description}")
        math(EXPR failures "${failures} + 1")
        set(failures ${failures} PARENT_SCOPE)
    endif()
endfunction()

function(expect_absent path needle description)
    file(READ "${repository_root}/${path}" contents)
    string(FIND "${contents}" "${needle}" position)
    if(NOT position EQUAL -1)
        message(SEND_ERROR "FAIL: ${description}")
    endif()
endfunction()

# Both consumers take the list; neither spells the target half out again.
expect_contains("cmake/recipes/ExportSysroot.cmake"
    "DEPENDS \${target_half_dependencies}"
    "the sysroot export does not wait for the target half")
expect_contains("cmake/recipes/FinalizeSdk.cmake"
    "\${target_half_dependencies})"
    "finalize-sdk does not wait for the target half")

# The splice belongs to the list and nowhere else, or the two drift again.
expect_absent("cmake/recipes/ExportSysroot.cmake" "softfp-shim"
    "ExportSysroot.cmake names softfp-shim itself instead of taking the list")
expect_absent("cmake/recipes/FinalizeSdk.cmake" "softfp-shim"
    "FinalizeSdk.cmake names softfp-shim itself instead of taking the list")

# The wrappers are assembled with the target compiler, so the recipe has to be
# included after whatever builds it. It named gcc-base, which the staged
# pipeline stopped building, and the dangling dependency went unnoticed until
# the target was first asked for -- make reported "No rule to make target
# 'gcc-base'" and took the whole sysroot with it.
expect_absent("cmake/recipes/SoftfpShims.cmake" "gcc-base"
    "the shim recipe still names gcc-base, which nothing builds")
expect_contains("cmake/recipes/SoftfpShims.cmake" "\${gcc_final_barrier}"
    "the shim recipe does not wait for the compiler that assembles it")

file(READ "${repository_root}/CMakeLists.txt" cmakelists)
string(FIND "${cmakelists}" "include(cmake/recipes/BuildGccFinal.cmake)" gcc_at)
string(FIND "${cmakelists}" "include(cmake/recipes/SoftfpShims.cmake)" shim_at)
if(shim_at LESS gcc_at)
    message(SEND_ERROR
        "FAIL: the shim recipe is included before the compiler it needs")
endif()

# A softfp world whose shims were never spliced is a toolchain that
# miscompiles quietly, so the list carries them exactly when the world is one.
expect_contains("CMakeLists.txt"
    "list(APPEND target_half_dependencies softfp-shim)"
    "the softfp splice is not part of the target half")
expect_contains("CMakeLists.txt"
    "VITASDK_FLOAT_ABI STREQUAL \"softfp\""
    "nothing decides when the splice belongs to the target half")

message(STATUS "target half dependency tests passed")
