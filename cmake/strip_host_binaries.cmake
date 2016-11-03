if (NOT WIN32)
    execute_process(COMMAND find "${BINDIR}" -maxdepth 1 -perm /u=x,g=x,o=x -and ! -type d
        OUTPUT_VARIABLE binaries
        OUTPUT_STRIP_TRAILING_WHITESPACE)
    string(REGEX REPLACE "\n" ";" binaries ${binaries})
else ()
    file(GLOB_RECURSE binaries "${BINDIR}/*exe")
endif ()

# set default strip command
if (NOT "${CMAKE_STRIP}")
    set(CMAKE_STRIP "strip")
endif ()

foreach (file ${binaries})
    message(STATUS "${CMAKE_STRIP} ${file}")
    execute_process(COMMAND ${CMAKE_STRIP} ${file})
endforeach ()
