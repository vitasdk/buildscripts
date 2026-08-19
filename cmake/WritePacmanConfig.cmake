if(NOT DEFINED OUTPUT OR NOT DEFINED HOST_ARCHITECTURE OR NOT DEFINED WORLD_ARCH)
    message(FATAL_ERROR "OUTPUT, HOST_ARCHITECTURE and WORLD_ARCH are required")
endif()

get_filename_component(output_directory "${OUTPUT}" DIRECTORY)
file(MAKE_DIRECTORY "${output_directory}")
set(temporary "${OUTPUT}.tmp")
file(WRITE "${temporary}"
    "[options]\n"
    "Architecture = ${HOST_ARCHITECTURE} ${WORLD_ARCH}\n"
    "# vdpm verifies signed channel metadata and the selected database hash before use.\n"
    "SigLevel = Never\n")
file(RENAME "${temporary}" "${OUTPUT}")
