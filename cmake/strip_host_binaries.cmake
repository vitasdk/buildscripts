if(NOT WIN32)
    # use an alternative perms format for find in OSX.
    if(${HOST_SYSTEM_NAME} STREQUAL "Darwin" OR ${HOST_SYSTEM_NAME} STREQUAL "FreeBSD")
        set(find_perms "+u=x,g=x,o=x")
    else()
        set(find_perms "/u=x,g=x,o=x")
    endif()

    execute_process(COMMAND find "${BINDIR}" -maxdepth 1 -perm ${find_perms} -and ! -type d
        OUTPUT_VARIABLE binaries
        OUTPUT_STRIP_TRAILING_WHITESPACE)
    string(REGEX REPLACE "\n" ";" binaries ${binaries})
else()
    file(GLOB_RECURSE binaries "${BINDIR}/*exe")
endif()

# set default strip command
if(NOT "${CMAKE_STRIP}")
    set(CMAKE_STRIP "strip")
endif()

foreach(executable ${binaries})
    execute_process(COMMAND ${CMAKE_STRIP} ${executable})
endforeach()
