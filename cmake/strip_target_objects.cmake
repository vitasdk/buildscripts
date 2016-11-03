# do not use quotes when passing the glob pattern
file(GLOB obj_libs ${PATTERN_GLOB})

foreach(obj ${obj_libs})
    execute_process(COMMAND ${OBJCOPY_COMMAND} -R .comment -R .note
        -R .debug_info -R .debug_aranges -R .debug_pubnames
        -R .debug_line -R .debug_pubtypes -R .debug_abbrev
        -R .debug_str -R .debug_ranges -R .debug_loc ${obj})
endforeach()
