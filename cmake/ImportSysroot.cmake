#
# Copyright(c) 2016 codestation
# Distributed under the MIT License (http://opensource.org/licenses/MIT)
#

# Script entry point for the stage-1 sysroot import. See SysrootManifest.cmake
# for the partition itself.

cmake_minimum_required(VERSION 3.16)

include("${CMAKE_CURRENT_LIST_DIR}/SysrootManifest.cmake")

foreach(argument STAGE1_DIR PREFIX TARGET_TRIPLE GCC_VERSION)
    if(NOT DEFINED ${argument})
        message(FATAL_ERROR "${argument} is required")
    endif()
endforeach()

vitasdk_import_sysroot("${STAGE1_DIR}" "${PREFIX}" "${TARGET_TRIPLE}" "${GCC_VERSION}")
