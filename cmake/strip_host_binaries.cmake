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
    set(strip_options)
    if("${HOST_SYSTEM_NAME}" STREQUAL "Darwin")
        execute_process(COMMAND file -b "${executable}"
            OUTPUT_VARIABLE file_type
            OUTPUT_STRIP_TRAILING_WHITESPACE)
        if(NOT file_type MATCHES "Mach-O")
            continue()
        endif()
        # Preserve externally referenced symbols in Mach-O bundles such as
        # GCC's LTO plugin while discarding local symbols.
        list(APPEND strip_options -x)
    elseif(NOT WIN32)
        execute_process(COMMAND file -b "${executable}"
            OUTPUT_VARIABLE file_type
            OUTPUT_STRIP_TRAILING_WHITESPACE)
        if(NOT file_type MATCHES "ELF")
            continue()
        endif()
    endif()

    execute_process(
        COMMAND ${CMAKE_STRIP} ${strip_options} "${executable}"
        RESULT_VARIABLE strip_result)
    if(NOT strip_result EQUAL 0)
        message(FATAL_ERROR "Unable to strip host binary: ${executable}")
    endif()
endforeach()
