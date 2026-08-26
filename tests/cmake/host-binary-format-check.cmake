cmake_minimum_required(VERSION 3.16)

# Helper for host-binary-format.cmake: runs the directory check in a process
# of its own so its FATAL_ERROR can be observed as a failure.

include("${CMAKE_CURRENT_LIST_DIR}/../../cmake/HostBinaryFormat.cmake")

vitasdk_check_binary_directory("${DIRECTORY}" "${SYSTEM}" "${TRIPLE}")
