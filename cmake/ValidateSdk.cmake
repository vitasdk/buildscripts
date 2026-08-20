if(NOT DEFINED SDK_DIR OR NOT DEFINED TARGET_TRIPLE)
    message(FATAL_ERROR "SDK_DIR and TARGET_TRIPLE are required")
endif()
if(NOT DEFINED HOST_SYSTEM_NAME)
    set(HOST_SYSTEM_NAME "${CMAKE_HOST_SYSTEM_NAME}")
endif()

set(required_tools gcc g++ ld as ar ranlib strip objcopy objdump readelf nm gdb)
foreach(tool IN LISTS required_tools)
    set(path "${SDK_DIR}/bin/${TARGET_TRIPLE}-${tool}")
    if(HOST_SYSTEM_NAME STREQUAL "Windows")
        set(path "${path}.exe")
    endif()
    if(NOT EXISTS "${path}")
        message(FATAL_ERROR "Missing SDK tool: ${path}")
    endif()
endforeach()

set(sysroot "${SDK_DIR}/${TARGET_TRIPLE}")
foreach(directory include lib)
    if(NOT IS_DIRECTORY "${sysroot}/${directory}")
        message(FATAL_ERROR "Missing sysroot directory: ${sysroot}/${directory}")
    endif()
endforeach()

# Everything in a bin directory must be a binary for this host. A staged
# build merges two machines into one tree, so this is where a producer's
# binary that rode along on an import gets caught.
if(DEFINED HOST_TRIPLE AND NOT HOST_TRIPLE STREQUAL "")
    include("${CMAKE_CURRENT_LIST_DIR}/HostBinaryFormat.cmake")
    vitasdk_check_binary_directory("${SDK_DIR}/bin" "${HOST_SYSTEM_NAME}" "${HOST_TRIPLE}")
    vitasdk_check_binary_directory("${sysroot}/bin" "${HOST_SYSTEM_NAME}" "${HOST_TRIPLE}")
endif()

if(DEFINED VERSION_FILE AND NOT EXISTS "${VERSION_FILE}")
    message(FATAL_ERROR "Missing provenance file: ${VERSION_FILE}")
endif()

message(STATUS "Validated SDK at ${SDK_DIR}")
