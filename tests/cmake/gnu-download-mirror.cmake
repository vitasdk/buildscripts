# Everything GNU hosts is named twice.
#
# One host was one host too few: ftp.gnu.org refused connections for over two
# minutes at a time through 26 and 27 August and took a whole build with it
# each time. Six components come from there and gdb is downloaded by every
# host, so a single outage is a red pipeline rather than a slow one.
#
# URL_HASH decides whether what came back is the right bytes, so a mirror
# serving something else fails the way a corrupt download does.

cmake_minimum_required(VERSION 3.16)

get_filename_component(repository_root "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
include("${repository_root}/cmake/Components.cmake")

foreach(component GCC GMP MPFR MPC BINUTILS GDB)
    set(urls "${${component}_URL}")
    list(LENGTH urls count)
    if(count LESS 3)
        message(SEND_ERROR
            "FAIL: ${component}_URL names ${count} host(s); two outages in a row is a "
            "failed build, and both happened on 27 August")
    endif()
    # ftp.gnu.org is the one that went down, so it is the last resort and not
    # the first thing tried.
    list(GET urls 0 first)
    if(first MATCHES "^https://ftp\\.gnu\\.org/")
        message(SEND_ERROR
            "FAIL: ${component}_URL tries ftp.gnu.org first")
    endif()
    list(GET urls -1 last)
    if(NOT last MATCHES "^https://ftp\\.gnu\\.org/")
        message(SEND_ERROR
            "FAIL: ${component}_URL does not keep ftp.gnu.org as the last resort: ${last}")
    endif()
    # And the hash, without which a mirror is somebody else's word for it.
    if(NOT DEFINED ${component}_HASH)
        message(SEND_ERROR "FAIL: ${component} has no hash to check a mirror against")
    endif()
endforeach()

message(STATUS "GNU download mirror tests passed")
