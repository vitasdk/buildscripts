# A launcher with arguments has to reach the command as arguments.
#
# The Rosetta gate runs the Intel macOS contract through `arch -x86_64`, and
# that arrives from the shell as one string. Interpolated into a VERBATIM
# COMMAND it became a single argv[0] with a space in it, so the run died with
#
#     no such file or directory
#
# naming nothing, after the whole SDK had been built and validated. The Intel
# host is cross-built, so this is the only thing that executes what it made.

cmake_minimum_required(VERSION 3.20)

include(${CMAKE_CURRENT_LIST_DIR}/../../cmake/HostRunner.cmake)

function(check_length description runner expected)
    vitasdk_host_runner_command(parts "${runner}")
    list(LENGTH parts length)
    if(NOT length EQUAL expected)
        message(SEND_ERROR "${description}: expected ${expected} argument(s), got ${length}: ${parts}")
    endif()
endfunction()

check_length("a host that runs its own binaries needs no launcher" "" 0)
check_length("a launcher with an argument stays two arguments" "arch -x86_64" 2)
check_length("a launcher with several arguments keeps them all" "qemu-aarch64 -L /sysroot" 3)

vitasdk_host_runner_command(runner_argv "arch -x86_64")
list(GET runner_argv 0 first)
if(NOT first STREQUAL "arch")
    message(SEND_ERROR "the launcher itself is not the first argument: ${first}")
endif()

# The shape the target uses, run for real: a two-word launcher, an
# environment, and a command behind it. cmake -E env is the launcher here
# because it exists wherever this test runs.
vitasdk_host_runner_command(launcher "${CMAKE_COMMAND} -E env")
execute_process(
    COMMAND ${CMAKE_COMMAND} -E env VITASDK=irrelevant
        ${launcher}
        ${CMAKE_COMMAND} -E echo the-contract-ran
    OUTPUT_VARIABLE output
    RESULT_VARIABLE status
    ERROR_VARIABLE errors)
string(STRIP "${output}" output)
if(NOT status EQUAL 0 OR NOT output STREQUAL "the-contract-ran")
    message(SEND_ERROR "a launcher with arguments did not reach the command: status ${status}, output '${output}', errors '${errors}'")
endif()

message(STATUS "host runner command: all checks passed")
