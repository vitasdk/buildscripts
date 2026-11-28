cmake_minimum_required(VERSION 3.16)

set(repository_root "${CMAKE_CURRENT_LIST_DIR}/../..")
string(RANDOM LENGTH 12 fixture_id)
if(DEFINED ENV{TMPDIR} AND NOT "$ENV{TMPDIR}" STREQUAL "")
    set(temp_root "$ENV{TMPDIR}")
elseif(DEFINED ENV{TEMP} AND NOT "$ENV{TEMP}" STREQUAL "")
    set(temp_root "$ENV{TEMP}")
else()
    set(temp_root "${CMAKE_CURRENT_BINARY_DIR}")
endif()
set(scratch "${temp_root}/vitasdk-windows-bin-contract-${fixture_id}")

function(write_pe path)
    file(WRITE "${path}" "MZ01234567890123456789")
endfunction()

function(populate_required_sdk sdk system_name)
    file(MAKE_DIRECTORY "${sdk}/bin" "${sdk}/arm-vita-eabi/include"
        "${sdk}/arm-vita-eabi/lib")
    set(suffix "")
    if(system_name STREQUAL "Windows")
        set(suffix ".exe")
    endif()
    foreach(tool gcc g++ ld as ar ranlib strip objcopy objdump readelf nm gdb)
        set(path "${sdk}/bin/arm-vita-eabi-${tool}${suffix}")
        if(system_name STREQUAL "Windows")
            write_pe("${path}")
        else()
            file(WRITE "${path}" "fixture")
        endif()
    endforeach()
    if(system_name STREQUAL "Windows")
        write_pe("${sdk}/bin/pkgconf.exe")
        write_pe("${sdk}/bin/arm-vita-eabi-pkg-config.exe")
    else()
        file(WRITE "${sdk}/bin/pkgconf" "fixture")
        file(WRITE "${sdk}/bin/arm-vita-eabi-pkg-config" "fixture")
    endif()
endfunction()

function(expect_policy_rejection name contents)
    set(directory "${scratch}/reject-${name}/bin")
    file(MAKE_DIRECTORY "${directory}")
    file(WRITE "${directory}/${name}" "${contents}")
    execute_process(
        COMMAND ${CMAKE_COMMAND}
            -DDIRECTORY=${directory}
            -P "${repository_root}/cmake/ValidateWindowsBin.cmake"
        RESULT_VARIABLE result
        OUTPUT_QUIET
        ERROR_VARIABLE error)
    if(result EQUAL 0)
        message(FATAL_ERROR "the Windows bin contract accepted ${name}")
    endif()
    if(NOT error MATCHES "${name}")
        message(FATAL_ERROR "the rejection did not name ${name}: ${error}")
    endif()
endfunction()

include("${repository_root}/cmake/HostBinaryFormat.cmake")

set(policy_bin "${scratch}/policy/bin")
file(MAKE_DIRECTORY "${policy_bin}/libmakepkg")
write_pe("${policy_bin}/native-tool.exe")
file(WRITE "${policy_bin}/makepkg.conf" "CARCH=\"vita\"\n")
file(WRITE "${policy_bin}/vita-makepkg" "#!/usr/bin/env sh\n")
file(WRITE "${policy_bin}/vitasdk-update" "#!/usr/bin/env sh\n")
file(WRITE "${policy_bin}/arm-vita-eabi-gdb-add-index" "#!/usr/bin/env sh\n")
file(WRITE "${policy_bin}/libmakepkg/internal-helper" "not top-level\n")
vitasdk_check_windows_top_level_bin("${policy_bin}")

expect_policy_rejection("unknown-script" "#!/usr/bin/env sh\n")
expect_policy_rejection("unknown-data" "not executable data\n")

set(windows_sdk "${scratch}/windows-sdk")
populate_required_sdk("${windows_sdk}" Windows)
file(WRITE "${windows_sdk}/bin/makepkg.conf" "CARCH=\"vita\"\n")
file(WRITE "${windows_sdk}/bin/vita-makepkg" "#!/usr/bin/env sh\n")
file(WRITE "${windows_sdk}/bin/vitasdk-update" "#!/usr/bin/env sh\n")
file(WRITE "${windows_sdk}/bin/arm-vita-eabi-gdb-add-index" "#!/usr/bin/env sh\n")
file(MAKE_DIRECTORY "${windows_sdk}/bin/libmakepkg")
file(WRITE "${windows_sdk}/bin/libmakepkg/internal-helper" "not top-level\n")

execute_process(
    COMMAND ${CMAKE_COMMAND}
        -DSDK_DIR=${windows_sdk}
        -DTARGET_TRIPLE=arm-vita-eabi
        -DHOST_SYSTEM_NAME=Windows
        -DHOST_TRIPLE=x86_64-w64-mingw32
        -P "${repository_root}/cmake/ValidateSdk.cmake"
    RESULT_VARIABLE valid_result
    OUTPUT_VARIABLE valid_output
    ERROR_VARIABLE valid_error)
if(NOT valid_result EQUAL 0)
    message(FATAL_ERROR
        "the staged validator rejected the Windows allowlist:\n${valid_output}${valid_error}")
endif()

file(WRITE "${windows_sdk}/bin/staged-unknown-script" "#!/usr/bin/env sh\n")
execute_process(
    COMMAND ${CMAKE_COMMAND}
        -DSDK_DIR=${windows_sdk}
        -DTARGET_TRIPLE=arm-vita-eabi
        -DHOST_SYSTEM_NAME=Windows
        -DHOST_TRIPLE=x86_64-w64-mingw32
        -P "${repository_root}/cmake/ValidateSdk.cmake"
    RESULT_VARIABLE invalid_result
    OUTPUT_QUIET
    ERROR_VARIABLE invalid_error)
if(invalid_result EQUAL 0)
    message(FATAL_ERROR "the staged validator accepted an unknown Windows bin script")
endif()
if(NOT invalid_error MATCHES "staged-unknown-script")
    message(FATAL_ERROR "the staged rejection omitted its path: ${invalid_error}")
endif()

set(linux_sdk "${scratch}/linux-sdk")
populate_required_sdk("${linux_sdk}" Linux)
file(WRITE "${linux_sdk}/bin/host-helper" "#!/usr/bin/env sh\n")
execute_process(
    COMMAND ${CMAKE_COMMAND}
        -DSDK_DIR=${linux_sdk}
        -DTARGET_TRIPLE=arm-vita-eabi
        -DHOST_SYSTEM_NAME=Linux
        -P "${repository_root}/cmake/ValidateSdk.cmake"
    RESULT_VARIABLE linux_result
    OUTPUT_VARIABLE linux_output
    ERROR_VARIABLE linux_error)
if(NOT linux_result EQUAL 0)
    message(FATAL_ERROR
        "the Windows-only contract changed Linux validation:\n${linux_output}${linux_error}")
endif()

file(REMOVE_RECURSE "${scratch}")
message(STATUS "Windows top-level bin contract checks passed")
