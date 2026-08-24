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
# Windows takes its static link through the libtool-safe flag below: a plain
# -static in these would tell libtool not to build gcc's LTO plugin DLL.
assert_flags(Windows
    "-static-libgcc"
    "-static-libgcc;-static-libstdc++"
    "-static-libgcc;-static-libstdc++")
# Darwin asks for nothing static -- its libgcc is not a separate library --
# but it does need the linker to stop preferring a dylib from any search path
# over the static dependencies built here.
assert_flags(Darwin "" "" "-Wl,-search_paths_first")

function(assert_libtool_flag system_name expected)
    vitasdk_get_libtool_static_flag("${system_name}" actual)
    if(NOT "${actual}" STREQUAL "${expected}")
        message(FATAL_ERROR
            "${system_name} libtool static flag: expected '${expected}', "
            "got '${actual}'")
    endif()
endfunction()

assert_libtool_flag(Linux "")
assert_libtool_flag(Darwin "")
assert_libtool_flag(Windows "--static")


message(STATUS "Static host-link policy checks passed")
