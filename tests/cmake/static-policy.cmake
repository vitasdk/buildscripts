cmake_minimum_required(VERSION 3.16)

include("${CMAKE_CURRENT_LIST_DIR}/../../cmake/StaticPolicy.cmake")

function(assert_flags system_name expected_c expected_cxx expected_link)
    vitasdk_get_host_static_flags("${system_name}" actual_c actual_cxx actual_link)
    foreach(kind c cxx link)
        if(NOT "${actual_${kind}}" STREQUAL "${expected_${kind}}")
            message(FATAL_ERROR
                "${system_name} ${kind} flags: expected '${expected_${kind}}', "
                "got '${actual_${kind}}'")
        endif()
    endforeach()
endfunction()

assert_flags(Linux
    "-static-libgcc"
    "-static-libgcc;-static-libstdc++"
    "-static-libgcc;-static-libstdc++")
assert_flags(Windows
    "-static-libgcc"
    "-static;-static-libgcc;-static-libstdc++"
    "-static;-static-libgcc;-static-libstdc++")
assert_flags(Darwin "" "" "")

function(assert_libtool_flag expected)
    vitasdk_get_libtool_static_flag(actual)
    if(NOT "${actual}" STREQUAL "${expected}")
        message(FATAL_ERROR
            "libtool static flag: expected '${expected}', got '${actual}'")
    endif()
endfunction()

assert_libtool_flag("")

# musl hosts request a fully static link (see cmake/toolchains/*-linux-musl.cmake)
set(VITASDK_FULLY_STATIC ON)
assert_flags(Linux
    "-static-libgcc"
    "-static;-static-libgcc;-static-libstdc++"
    "-static;-static-libgcc;-static-libstdc++")
# The double dash is load-bearing: libtool drops a plain -static in link mode
# and binutils ships programs needing libc.so. Do not tidy it to one dash.
assert_libtool_flag("--static")
unset(VITASDK_FULLY_STATIC)

message(STATUS "Static host-link policy checks passed")
