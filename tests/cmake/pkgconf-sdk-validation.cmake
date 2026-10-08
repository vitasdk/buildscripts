cmake_minimum_required(VERSION 3.19)

set(validate_script "${CMAKE_CURRENT_LIST_DIR}/../../cmake/ValidateSdk.cmake")
set(required_tools gcc g++ ld as ar ranlib strip objcopy objdump readelf nm gdb)

function(create_sdk_fixture root suffix)
    file(REMOVE_RECURSE "${root}")
    file(MAKE_DIRECTORY "${root}/bin" "${root}/arm-vita-eabi/include" "${root}/arm-vita-eabi/lib")
    foreach(tool IN LISTS required_tools)
        file(WRITE "${root}/bin/arm-vita-eabi-${tool}${suffix}" "")
    endforeach()
endfunction()

function(run_validation root system_name expected_success)
    execute_process(
        COMMAND "${CMAKE_COMMAND}"
            -DSDK_DIR=${root}
            -DTARGET_TRIPLE=arm-vita-eabi
            -DHOST_SYSTEM_NAME=${system_name}
            -P "${validate_script}"
        RESULT_VARIABLE result
        OUTPUT_VARIABLE output
        ERROR_VARIABLE error)
    if(expected_success AND NOT result EQUAL 0)
        message(FATAL_ERROR "${system_name} validation failed unexpectedly:\n${output}${error}")
    endif()
    if(NOT expected_success AND result EQUAL 0)
        message(FATAL_ERROR "${system_name} validation accepted an SDK without the pkg-config frontend/backend")
    endif()
endfunction()

set(test_root "${CMAKE_CURRENT_BINARY_DIR}/pkgconf-sdk-validation")

set(unix_root "${test_root}/unix")
create_sdk_fixture("${unix_root}" "")
run_validation("${unix_root}" Linux FALSE)
file(WRITE "${unix_root}/bin/pkgconf" "")
file(WRITE "${unix_root}/bin/arm-vita-eabi-pkg-config" "")
run_validation("${unix_root}" Linux TRUE)

set(windows_root "${test_root}/windows")
create_sdk_fixture("${windows_root}" ".exe")
run_validation("${windows_root}" Windows FALSE)
file(WRITE "${windows_root}/bin/pkgconf.exe" "")
file(WRITE "${windows_root}/bin/arm-vita-eabi-pkg-config.exe" "")
run_validation("${windows_root}" Windows TRUE)

file(REMOVE_RECURSE "${test_root}")
message(STATUS "pkgconf SDK validation checks passed")
