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

message(STATUS "Static host-link policy checks passed")
