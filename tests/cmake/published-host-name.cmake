cmake_minimum_required(VERSION 3.16)

include("${CMAKE_CURRENT_LIST_DIR}/../../cmake/PublishedHostName.cmake")

function(assert_published triplet expected)
    vitasdk_published_host_name("${triplet}" actual)
    if(NOT "${actual}" STREQUAL "${expected}")
        message(FATAL_ERROR
            "${triplet} publishes as '${actual}', expected '${expected}'")
    endif()
endfunction()

assert_published(x86_64-unknown-freebsd14 x86_64-unknown-freebsd)
assert_published(aarch64-unknown-freebsd14 aarch64-unknown-freebsd)

# Every other host publishes under the triplet it builds with.
foreach(triplet x86_64-linux-gnu aarch64-linux-gnu x86_64-linux-musl
        aarch64-linux-musl arm64-apple-darwin x86_64-apple-darwin
        x86_64-w64-mingw32)
    assert_published("${triplet}" "${triplet}")
endforeach()

# The gate: a name may only be published by the toolchain that earns it.
function(assert_gate published triplet expected_result)
    execute_process(
        COMMAND ${CMAKE_COMMAND}
            -DPUBLISHED=${published} -DTRIPLET=${triplet}
            -P "${CMAKE_CURRENT_LIST_DIR}/published-host-name-check.cmake"
        RESULT_VARIABLE result
        OUTPUT_QUIET
        ERROR_VARIABLE error)
    if(expected_result STREQUAL "accepts" AND NOT result EQUAL 0)
        message(FATAL_ERROR "${triplet} must publish as ${published}: ${error}")
    endif()
    if(expected_result STREQUAL "rejects")
        if(result EQUAL 0)
            message(FATAL_ERROR "${triplet} must not publish as ${published}")
        endif()
        if(NOT error MATCHES "${published}" OR NOT error MATCHES "${triplet}")
            message(FATAL_ERROR "the rejection must name both, got: ${error}")
        endif()
    endif()
endfunction()

assert_gate(x86_64-linux-gnu x86_64-linux-gnu accepts)
assert_gate(x86_64-unknown-freebsd x86_64-unknown-freebsd14 accepts)
# Apple's spelling of the machine config.sub calls aarch64.
assert_gate(arm64-apple-darwin aarch64-apple-darwin accepts)
assert_gate(aarch64-apple-darwin arm64-apple-darwin accepts)

# What shipped an arm64 SDK under the Intel name: the cross host lost its
# toolchain file, so the build named one host and produced another.
assert_gate(x86_64-apple-darwin arm64-apple-darwin rejects)
assert_gate(arm64-apple-darwin x86_64-apple-darwin rejects)
assert_gate(x86_64-w64-mingw32 x86_64-linux-gnu rejects)
assert_gate(aarch64-linux-gnu x86_64-linux-gnu rejects)

message(STATUS "published host name checks passed")
