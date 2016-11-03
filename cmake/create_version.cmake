string(TIMESTAMP BUILD_DATE "%Y-%m-%d %H:%M:%S" UTC)

file(READ ${INPUT_DIR}/vita-toolchain-version.txt _toolchain_sha1)
file(READ ${INPUT_DIR}/vita-headers-version.txt _headers_sha1)
file(READ ${INPUT_DIR}/newlib-version.txt _newlib_sha1)
file(READ ${INPUT_DIR}/pthread-embedded-version.txt _pthread_sha1)
file(READ ${INPUT_DIR}/samples-version.txt _samples_sha1)

file(WRITE ${OUTPUT_DIR}/version_info.txt "Built at ${BUILD_DATE}\n")
file(APPEND ${OUTPUT_DIR}/version_info.txt "newlib            ${_newlib_sha1}")
file(APPEND ${OUTPUT_DIR}/version_info.txt "pthread-embedded  ${_pthread_sha1}")
file(APPEND ${OUTPUT_DIR}/version_info.txt "samples           ${_samples_sha1}")
file(APPEND ${OUTPUT_DIR}/version_info.txt "vita-headers      ${_headers_sha1}")
file(APPEND ${OUTPUT_DIR}/version_info.txt "vita-toolchain    ${_toolchain_sha1}")
