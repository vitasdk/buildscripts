# do not use quotes when passing the glob pattern
file(GLOB obj_libs ${PATTERN_GLOB})

foreach(obj ${obj_libs})
    execute_process(
        COMMAND ${OBJCOPY_COMMAND} --strip-debug -R .comment -R .note "${obj}"
        RESULT_VARIABLE objcopy_result)
    if(NOT objcopy_result EQUAL 0)
        message(FATAL_ERROR "Unable to strip target object or archive: ${obj}")
    endif()
endforeach()
