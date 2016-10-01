# do not use quotes when passing the glob pattern
file(GLOB FILE_LIST ${GLOB_PATTERN})
file(INSTALL ${FILE_LIST} DESTINATION "${INSTALL_DIR}"
    PATTERN ".git" EXCLUDE
    PATTERN ".gitignore" EXCLUDE)
