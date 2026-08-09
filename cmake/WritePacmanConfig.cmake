if(NOT DEFINED OUTPUT OR NOT DEFINED HOST_ARCHITECTURE)
    message(FATAL_ERROR "OUTPUT and HOST_ARCHITECTURE are required")
endif()

get_filename_component(output_directory "${OUTPUT}" DIRECTORY)
file(MAKE_DIRECTORY "${output_directory}")
set(temporary "${OUTPUT}.tmp")
file(WRITE "${temporary}"
    "[options]\n"
    "Architecture = ${HOST_ARCHITECTURE} vita\n"
    "# vdpm verifies signed channel metadata and the selected database hash before use.\n"
    "SigLevel = Never\n")
file(RENAME "${temporary}" "${OUTPUT}")
