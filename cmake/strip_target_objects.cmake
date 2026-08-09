# do not use quotes when passing the glob pattern
file(GLOB obj_libs ${PATTERN_GLOB})

foreach(obj ${obj_libs})
    get_filename_component(obj_name "${obj}" NAME)
    # GCC installs this host-side plugin archive below its target-version
    # directory. In a cross-built Windows SDK it contains PE/COFF objects,
    # which the Vita objcopy must neither recognize nor modify.
    if(SKIP_GCC_LTO_PLUGIN AND
            (obj_name STREQUAL "liblto_plugin.a" OR
             obj_name STREQUAL "liblto_plugin.dll.a"))
        continue()
    endif()
    execute_process(
        COMMAND ${OBJCOPY_COMMAND} --strip-debug -R .comment -R .note "${obj}"
        RESULT_VARIABLE objcopy_result)
    if(NOT objcopy_result EQUAL 0)
        message(FATAL_ERROR "Unable to strip target object or archive: ${obj}")
    endif()
endforeach()
