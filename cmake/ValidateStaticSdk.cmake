if(NOT DEFINED SDK_DIR OR NOT DEFINED TARGET_TRIPLE)
    message(FATAL_ERROR "SDK_DIR and TARGET_TRIPLE are required")
endif()

set(target_library_roots
    "${SDK_DIR}/${TARGET_TRIPLE}/lib"
    "${SDK_DIR}/lib/gcc/${TARGET_TRIPLE}")

foreach(root IN LISTS target_library_roots)
    if(NOT IS_DIRECTORY "${root}")
        message(FATAL_ERROR "Missing target library directory: ${root}")
    endif()
endforeach()

set(target_shared)
foreach(root IN LISTS target_library_roots)
    file(GLOB_RECURSE root_shared
        "${root}/*.so"
        "${root}/*.so.*"
        "${root}/*.dylib"
        "${root}/*.dll"
        "${root}/*.dll.a")
    list(APPEND target_shared ${root_shared})
endforeach()

# GCC installs host-side LTO and debugger plugins below its target-version
# directory.  Their .so suffix describes the plugin ABI, not the target ABI;
# they are checked by audit-host-deps.sh along with the other host binaries.
file(GLOB_RECURSE host_gcc_plugins
    "${SDK_DIR}/lib/gcc/${TARGET_TRIPLE}/*/liblto_plugin*.so"
    "${SDK_DIR}/lib/gcc/${TARGET_TRIPLE}/*/liblto_plugin*.dylib"
    "${SDK_DIR}/lib/gcc/${TARGET_TRIPLE}/*/liblto_plugin*.dll"
    "${SDK_DIR}/lib/gcc/${TARGET_TRIPLE}/*/plugin/libcc1plugin*.so"
    "${SDK_DIR}/lib/gcc/${TARGET_TRIPLE}/*/plugin/libcc1plugin*.dylib"
    "${SDK_DIR}/lib/gcc/${TARGET_TRIPLE}/*/plugin/libcc1plugin*.dll"
    "${SDK_DIR}/lib/gcc/${TARGET_TRIPLE}/*/plugin/libcp1plugin*.so"
    "${SDK_DIR}/lib/gcc/${TARGET_TRIPLE}/*/plugin/libcp1plugin*.dylib"
    "${SDK_DIR}/lib/gcc/${TARGET_TRIPLE}/*/plugin/libcp1plugin*.dll")
list(REMOVE_ITEM target_shared ${host_gcc_plugins})

if(target_shared)
    string(JOIN "\n  " shared_list ${target_shared})
    message(FATAL_ERROR
        "Target sysroot contains shared libraries or import archives:\n  ${shared_list}")
endif()

set(required_archives
    libc.a
    libm.a
    libpthread.a
    libgcc.a
    libstdc++.a
    libsupc++.a
    libgomp.a)

foreach(archive IN LISTS required_archives)
    set(matches)
    foreach(root IN LISTS target_library_roots)
        file(GLOB_RECURSE root_matches "${root}/${archive}")
        list(APPEND matches ${root_matches})
    endforeach()
    if(NOT matches)
        message(FATAL_ERROR "Missing required target static archive: ${archive}")
    endif()
endforeach()

file(GLOB_RECURSE vita_stub_archives
    "${SDK_DIR}/${TARGET_TRIPLE}/lib/libSce*_stub.a")
if(NOT vita_stub_archives)
    message(FATAL_ERROR "No Vita SDK stub archives were installed")
endif()

message(STATUS
    "Static target SDK validation passed (${required_archives}; Vita stubs present)")
