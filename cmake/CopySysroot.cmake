#
# Copyright(c) 2016 codestation
# Distributed under the MIT License (http://opensource.org/licenses/MIT)
#

# Script entry point for moving the target half of an SDK between trees, in
# either direction. See SysrootManifest.cmake for the partition itself.

cmake_minimum_required(VERSION 3.16)

include("${CMAKE_CURRENT_LIST_DIR}/SysrootManifest.cmake")

foreach(argument SOURCE DESTINATION TARGET_TRIPLE GCC_VERSION)
    if(NOT DEFINED ${argument})
        message(FATAL_ERROR "${argument} is required")
    endif()
endforeach()

vitasdk_copy_sysroot("${SOURCE}" "${DESTINATION}" "${TARGET_TRIPLE}" "${GCC_VERSION}")
