if (NOT WIN32)
    # use an alternative perms format for find in OSX.
    if (${HOST_SYSTEM_NAME} STREQUAL "Darwin")
        set(FIND_PERMS "+u=x,g=x,o=x")
    else ()
        set(FIND_PERMS "/u=x,g=x,o=x")
    endif ()

    execute_process(COMMAND find "${BINDIR}" -maxdepth 1 -perm ${FIND_PERMS} -and ! -type d
        OUTPUT_VARIABLE BINARIES
        OUTPUT_STRIP_TRAILING_WHITESPACE)
    string(REGEX REPLACE "\n" ";" BINARIES ${BINARIES})
else ()
    file(GLOB_RECURSE BINARIES "${BINDIR}/*exe")
endif ()

# set default strip command
if (NOT "${CMAKE_STRIP}")
    set(CMAKE_STRIP "strip")
endif ()

foreach (EXECUTABLE ${BINARIES})
    message(STATUS "${CMAKE_STRIP} ${EXECUTABLE}")
    execute_process(COMMAND ${CMAKE_STRIP} ${EXECUTABLE})
endforeach ()
