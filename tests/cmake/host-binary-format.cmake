cmake_minimum_required(VERSION 3.16)

include("${CMAKE_CURRENT_LIST_DIR}/../../cmake/HostBinaryFormat.cmake")

function(assert_decode hex expected_format expected_machine)
    vitasdk_decode_binary_format("${hex}" format machine)
    if(NOT format STREQUAL expected_format)
        message(FATAL_ERROR "${hex}: expected format '${expected_format}', got '${format}'")
    endif()
    if(NOT machine STREQUAL expected_machine)
        message(FATAL_ERROR "${hex}: expected machine '${expected_machine}', got '${machine}'")
    endif()
endfunction()

# ELF64 little endian, e_machine at offset 18: x86-64, aarch64, ARM.
assert_decode("7F454C4602010100000000000000000002003E00" ELF 62)
assert_decode("7F454C460201010000000000000000000200B700" ELF 183)
assert_decode("7F454C4601010100000000000000000002002800" ELF 40)
# ELF big endian keeps e_machine in its own byte order.
assert_decode("7F454C4602020100000000000000000000020016" ELF 22)
assert_decode("4D5A90000300000004000000FFFF0000B8000000" PE "")
# Mach-O 64, little endian: the cputype follows the magic in its byte order.
assert_decode("CFFAEDFE0C000001000000000200000013000000" MachO 16777228)
assert_decode("CFFAEDFE07000001030000000200000013000000" MachO 16777223)
assert_decode("FEEDFACF010000070000000300000002000000A0" MachO 16777223)
# A universal binary has a cputype per slice and none of its own.
assert_decode("CAFEBABE0000000201000007000000030000C000" MachO "")
# A shell script is in no executable format and must decode as nothing.
assert_decode("23212F62696E2F73680A6563686F206869" "" "")

function(assert_expected system triple expected_format expected_machine)
    vitasdk_expected_binary_format("${system}" "${triple}" format machine)
    if(NOT format STREQUAL expected_format OR NOT machine STREQUAL expected_machine)
        message(FATAL_ERROR
            "${system}/${triple}: expected ${expected_format}/${expected_machine}, "
            "got ${format}/${machine}")
    endif()
endfunction()

assert_expected(Windows x86_64-w64-mingw32 PE "")
assert_expected(Darwin arm64-apple-darwin MachO 16777228)
assert_expected(Darwin aarch64-apple-darwin MachO 16777228)
assert_expected(Darwin x86_64-apple-darwin MachO 16777223)
assert_expected(Linux x86_64-linux-gnu ELF 62)
assert_expected(Linux i686-linux-gnu ELF 3)
assert_expected(Linux aarch64-linux-musl ELF 183)
assert_expected(FreeBSD x86_64-unknown-freebsd ELF 62)

# A real host executable, to prove the reader agrees with the machine it runs on.
vitasdk_binary_format("${CMAKE_COMMAND}" format machine)
vitasdk_expected_binary_format("${CMAKE_HOST_SYSTEM_NAME}" "${CMAKE_HOST_SYSTEM_PROCESSOR}"
    expected_format expected_machine)
if(NOT format STREQUAL expected_format)
    message(FATAL_ERROR
        "cmake itself reads as ${format} on ${CMAKE_HOST_SYSTEM_NAME}, expected ${expected_format}")
endif()

# The failure this whole check exists for: a stage-1 Linux binutils riding
# along into a Windows SDK.
string(RANDOM LENGTH 12 fixture_id)
if(DEFINED ENV{TMPDIR} AND NOT "$ENV{TMPDIR}" STREQUAL "")
    set(temp_root "$ENV{TMPDIR}")
elseif(DEFINED ENV{TEMP} AND NOT "$ENV{TEMP}" STREQUAL "")
    set(temp_root "$ENV{TEMP}")
else()
    set(temp_root "${CMAKE_CURRENT_BINARY_DIR}")
endif()
set(scratch "${temp_root}/vitasdk-host-binary-format-${fixture_id}")
file(WRITE "${scratch}/bin/ld.exe" "MZ and enough bytes to read a header from")
file(WRITE "${scratch}/bin/README" "not a binary at all")
vitasdk_check_binary_directory("${scratch}/bin" Windows x86_64-w64-mingw32)
get_filename_component(real_cmake "${CMAKE_COMMAND}" REALPATH)
file(COPY "${real_cmake}" DESTINATION "${scratch}/bin")
execute_process(
    COMMAND ${CMAKE_COMMAND}
        -DDIRECTORY=${scratch}/bin
        -DSYSTEM=Windows -DTRIPLE=x86_64-w64-mingw32
        -P "${CMAKE_CURRENT_LIST_DIR}/host-binary-format-check.cmake"
    RESULT_VARIABLE check_result
    OUTPUT_QUIET
    ERROR_VARIABLE check_error)
if(check_result EQUAL 0)
    message(FATAL_ERROR "a foreign host binary must be rejected")
endif()
if(NOT check_error MATCHES "in a PE SDK")
    message(FATAL_ERROR "the rejection must name both formats, got: ${check_error}")
endif()
file(REMOVE_RECURSE "${scratch}")

# The machine half of the same failure, which format alone cannot see: both
# Macs produce Mach-O, so on the one host pair that is staged across two
# architectures nothing else would catch it. The fixture is the real cmake,
# so the bytes are a machine's own rather than a hand-written header, and the
# foreign triple is picked by what it is not -- script mode knows the host
# system name but not its processor.
set(foreign_triple "")
if(NOT machine STREQUAL "")
    foreach(arch x86_64 aarch64)
        if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin")
            set(candidate ${arch}-apple-darwin)
        elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
            set(candidate ${arch}-linux-gnu)
        else()
            break()
        endif()
        vitasdk_expected_binary_format("${CMAKE_HOST_SYSTEM_NAME}" "${candidate}"
            candidate_format candidate_machine)
        if(NOT candidate_machine EQUAL machine)
            set(foreign_triple ${candidate})
            break()
        endif()
    endforeach()
endif()
if(NOT foreign_triple STREQUAL "")
    set(scratch "${temp_root}/vitasdk-host-binary-machine-${fixture_id}")
    file(COPY "${real_cmake}" DESTINATION "${scratch}/bin")
    execute_process(
        COMMAND ${CMAKE_COMMAND}
            -DDIRECTORY=${scratch}/bin
            -DSYSTEM=${CMAKE_HOST_SYSTEM_NAME}
            -DTRIPLE=${foreign_triple}
            -P "${CMAKE_CURRENT_LIST_DIR}/host-binary-format-check.cmake"
        RESULT_VARIABLE check_result
        OUTPUT_QUIET
        ERROR_VARIABLE check_error)
    if(check_result EQUAL 0)
        message(FATAL_ERROR "a binary for another machine must be rejected")
    endif()
    if(NOT check_error MATCHES "machine ${machine}" OR NOT check_error MATCHES "${foreign_triple}")
        message(FATAL_ERROR "the rejection must name the machine, got: ${check_error}")
    endif()
    file(REMOVE_RECURSE "${scratch}")
endif()

message(STATUS "Host binary format checks passed")
