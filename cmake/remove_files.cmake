# Do not follow symlinks
cmake_policy(SET CMP0009 NEW)

file(GLOB_RECURSE file_list ${GLOB_PATTERN})

if(file_list)
    file(REMOVE ${file_list})
endif()
