# do not use quotes when passing the glob pattern
file(GLOB file_list ${GLOB_PATTERN})

if(file_list)
    file(INSTALL ${file_list} DESTINATION "${INSTALL_DIR}"
        PATTERN ".git" EXCLUDE
        PATTERN ".gitignore" EXCLUDE)
endif()
