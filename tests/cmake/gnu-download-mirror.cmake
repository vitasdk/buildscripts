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
    if(count LESS 2)
        message(SEND_ERROR
            "FAIL: ${component}_URL names one host; an outage there is a failed build")
    endif()
    list(GET urls 0 first)
    if(NOT first MATCHES "^https://ftpmirror\\.gnu\\.org/")
        message(SEND_ERROR
            "FAIL: ${component}_URL does not try GNU's mirror redirector first: ${first}")
    endif()
    # And the hash, without which a mirror is somebody else's word for it.
    if(NOT DEFINED ${component}_HASH)
        message(SEND_ERROR "FAIL: ${component} has no hash to check a mirror against")
    endif()
endforeach()

message(STATUS "GNU download mirror tests passed")
