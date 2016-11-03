file(INSTALL ${SOURCE} DESTINATION ${DEST}
    PATTERN ".git" EXCLUDE
    PATTERN "../.gitignore" EXCLUDE
    )
