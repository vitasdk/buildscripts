if(NOT DEFINED DIRECTORY)
    message(FATAL_ERROR "DIRECTORY is required")
endif()

include("${CMAKE_CURRENT_LIST_DIR}/HostBinaryFormat.cmake")
vitasdk_check_windows_top_level_bin("${DIRECTORY}")
