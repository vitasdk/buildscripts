cmake_minimum_required(VERSION 3.16)

include("${CMAKE_CURRENT_LIST_DIR}/../../cmake/PublishedHostName.cmake")

vitasdk_check_published_host_name("${PUBLISHED}" "${TRIPLET}")
