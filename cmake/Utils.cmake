# Loads all the CMAKE_X_FLAGS to a single list to it can be passed
# to the command_Wrapper script.
function(LOAD_FLAGS FLAGS)
    if(CMAKE_BUILD_TYPE STREQUAL "Release")
        list(APPEND _FLAGS
            _CFLAGS=${CMAKE_C_FLAGS_RELEASE}
            _CXXFLAGS=${CMAKE_CXX_FLAGS_RELEASE}
            _CPPFLAGS=${CMAKE_CPP_FLAGS_RELEASE}
            _LDFLAGS=${CMAKE_LD_FLAGS_RELEASE})
        string(REPLACE "-O3" "-O2" _FLAGS "${_FLAGS}")
    elseif(CMAKE_BUILD_TYPE STREQUAL "Debug")
        list(APPEND _FLAGS
            _CFLAGS=${CMAKE_C_FLAGS_DEBUG}
            _CXXFLAGS=${CMAKE_CXX_FLAGS_DEBUG}
            _CPPFLAGS=${CMAKE_CPP_FLAGS_DEBUG}
            _LDFLAGS=${CMAKE_LD_FLAGS_DEBUG})
    else()
        list(APPEND _FLAGS
            _CFLAGS=${CMAKE_C_FLAGS}
            _CXXFLAGS=${CMAKE_CXX_FLAGS}
            _CPPFLAGS=${CMAKE_CPP_FLAGS}
            _LDFLAGS=${CMAKE_LD_FLAGS})
    endif()

    set(${FLAGS} ${_FLAGS} PARENT_SCOPE)
endfunction()
