file(GLOB binaries "${BINDIR}/*.a" "${BINDIR}/*.o")

foreach (file ${binaries})
    message(STATUS "${OBJCOPY_CMD} ${file}")
    execute_process(COMMAND ${OBJCOPY_CMD} -R .comment -R .note
        -R .debug_info -R .debug_aranges -R .debug_pubnames
        -R .debug_pubtypes -R .debug_abbrev -R .debug_line -R .debug_str
        -R .debug_ranges -R .debug_loc ${file})
endforeach ()
