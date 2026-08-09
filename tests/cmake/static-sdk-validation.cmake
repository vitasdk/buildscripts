string(RANDOM LENGTH 12 fixture_id)
if(DEFINED ENV{TMPDIR} AND NOT "$ENV{TMPDIR}" STREQUAL "")
    set(temp_root "$ENV{TMPDIR}")
elseif(DEFINED ENV{TEMP} AND NOT "$ENV{TEMP}" STREQUAL "")
    set(temp_root "$ENV{TEMP}")
else()
    set(temp_root "${CMAKE_CURRENT_BINARY_DIR}")
endif()
set(fixture "${temp_root}/vitasdk-static-validation-${fixture_id}")
set(target_triple arm-vita-eabi)
set(target_lib "${fixture}/${target_triple}/lib")
set(target_include "${fixture}/${target_triple}/include")
set(gcc_lib "${fixture}/lib/gcc/${target_triple}/15.2.0")

file(MAKE_DIRECTORY "${target_lib}" "${target_include}" "${gcc_lib}/plugin")
foreach(archive
        libc.a libm.a libpthread.a libgcc.a libstdc++.a libsupc++.a libgomp.a)
    file(WRITE "${target_lib}/${archive}" "")
endforeach()
file(WRITE "${target_lib}/libSceKernel_stub.a" "")

# ValidateSdk runs through the build machine's CMake during cross builds, so
# the product system must select the executable suffix explicitly.
file(MAKE_DIRECTORY "${fixture}/bin")
foreach(tool gcc g++ ld as ar ranlib strip objcopy objdump readelf nm gdb)
    file(WRITE "${fixture}/bin/${target_triple}-${tool}.exe" "")
endforeach()
execute_process(
    COMMAND "${CMAKE_COMMAND}"
        -DSDK_DIR=${fixture}
        -DTARGET_TRIPLE=${target_triple}
        -DHOST_SYSTEM_NAME=Windows
        -P ${CMAKE_CURRENT_LIST_DIR}/../../cmake/ValidateSdk.cmake
    RESULT_VARIABLE windows_layout_result
    OUTPUT_VARIABLE windows_layout_output
    ERROR_VARIABLE windows_layout_error)
if(NOT windows_layout_result EQUAL 0)
    file(REMOVE_RECURSE "${fixture}")
    message(FATAL_ERROR
        "Windows SDK layout with .exe tools was rejected:\n${windows_layout_output}${windows_layout_error}")
endif()

set(strip_fixture "${fixture}/strip-fixture")
file(MAKE_DIRECTORY "${strip_fixture}")
file(WRITE "${strip_fixture}/liblto_plugin.a" "")
execute_process(
    COMMAND "${CMAKE_COMMAND}"
        -DOBJCOPY_COMMAND=vitasdk-deliberately-missing-objcopy
        "-DPATTERN_GLOB=${strip_fixture}/*.a"
        -DSKIP_GCC_LTO_PLUGIN=ON
        -P ${CMAKE_CURRENT_LIST_DIR}/../../cmake/strip_target_objects.cmake
    RESULT_VARIABLE host_plugin_strip_result
    OUTPUT_QUIET
    ERROR_QUIET)
if(NOT host_plugin_strip_result EQUAL 0)
    file(REMOVE_RECURSE "${fixture}")
    message(FATAL_ERROR "Target stripping attempted to process the host LTO plugin archive")
endif()

# The LTO plugin is a host plugin despite living below GCC's target-version
# directory. Versioned spellings emitted by different hosts are all valid.
file(WRITE "${gcc_lib}/liblto_plugin.so" "")
file(WRITE "${gcc_lib}/liblto_plugin.so.0" "")
file(WRITE "${gcc_lib}/liblto_plugin.so.0.0.0" "")

execute_process(
    COMMAND "${CMAKE_COMMAND}"
        -DSDK_DIR=${fixture}
        -DTARGET_TRIPLE=${target_triple}
        -P ${CMAKE_CURRENT_LIST_DIR}/../../cmake/ValidateStaticSdk.cmake
    RESULT_VARIABLE valid_result
    OUTPUT_VARIABLE valid_output
    ERROR_VARIABLE valid_error)
if(NOT valid_result EQUAL 0)
    file(REMOVE_RECURSE "${fixture}")
    message(FATAL_ERROR
        "Static SDK fixture with the host LTO plugin was rejected:\n${valid_output}${valid_error}")
endif()

file(WRITE "${gcc_lib}/plugin/libcc1plugin.so.0.0.0" "")
execute_process(
    COMMAND "${CMAKE_COMMAND}"
        -DSDK_DIR=${fixture}
        -DTARGET_TRIPLE=${target_triple}
        -P ${CMAKE_CURRENT_LIST_DIR}/../../cmake/ValidateStaticSdk.cmake
    RESULT_VARIABLE libcc1_result
    OUTPUT_QUIET
    ERROR_QUIET)
if(libcc1_result EQUAL 0)
    file(REMOVE_RECURSE "${fixture}")
    message(FATAL_ERROR "Static SDK validation accepted a disabled libcc1 plugin")
endif()
file(REMOVE "${gcc_lib}/plugin/libcc1plugin.so.0.0.0")

file(WRITE "${target_lib}/libunexpected.so" "")
execute_process(
    COMMAND "${CMAKE_COMMAND}"
        -DSDK_DIR=${fixture}
        -DTARGET_TRIPLE=${target_triple}
        -P ${CMAKE_CURRENT_LIST_DIR}/../../cmake/ValidateStaticSdk.cmake
    RESULT_VARIABLE invalid_result
    OUTPUT_QUIET
    ERROR_QUIET)
file(REMOVE_RECURSE "${fixture}")

if(invalid_result EQUAL 0)
    message(FATAL_ERROR "Static SDK validation accepted a target shared library")
endif()

message(STATUS "Static SDK validation checks passed")
