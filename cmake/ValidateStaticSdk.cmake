if(NOT DEFINED SDK_DIR OR NOT DEFINED TARGET_TRIPLE)
    message(FATAL_ERROR "SDK_DIR and TARGET_TRIPLE are required")
endif()

set(target_libdir "${SDK_DIR}/${TARGET_TRIPLE}/lib")
if(NOT IS_DIRECTORY "${target_libdir}")
    message(FATAL_ERROR "Missing target library directory: ${target_libdir}")
endif()

file(GLOB_RECURSE target_shared
    "${target_libdir}/*.so"
    "${target_libdir}/*.so.*"
    "${target_libdir}/*.dylib"
    "${target_libdir}/*.dll")

if(target_shared)
    string(JOIN "\n  " shared_list ${target_shared})
    message(FATAL_ERROR
        "Target sysroot contains shared libraries:\n  ${shared_list}")
endif()

file(GLOB_RECURSE target_archives "${target_libdir}/*.a")
if(NOT target_archives)
    message(FATAL_ERROR "No target static archives found in ${target_libdir}")
endif()

message(STATUS "Static target sysroot validation passed")
