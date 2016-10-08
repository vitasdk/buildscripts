file(GLOB_RECURSE file_list ${GLOB_PATTERN})

if(file_list)
    file(REMOVE ${file_list})
endif()
