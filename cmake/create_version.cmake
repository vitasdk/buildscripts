string(TIMESTAMP BUILD_DATE "%Y-%m-%d %H:%M:%S" UTC)

file(READ ${INPUT_DIR}/vita-toolchain-version.txt _toolchain_sha1)
file(READ ${INPUT_DIR}/vita-headers-version.txt _headers_sha1)
file(READ ${INPUT_DIR}/musl-version.txt _musl_sha1)
file(READ ${INPUT_DIR}/samples-version.txt _samples_sha1)

file(WRITE ${OUTPUT_FILE} "Built at ${BUILD_DATE}\n")
file(APPEND ${OUTPUT_FILE} "musl            ${_musl_sha1}")
file(APPEND ${OUTPUT_FILE} "samples           ${_samples_sha1}")
file(APPEND ${OUTPUT_FILE} "vita-headers      ${_headers_sha1}")
file(APPEND ${OUTPUT_FILE} "vita-toolchain    ${_toolchain_sha1}")
