include_guard(GLOBAL)

# Keep host tools portable without attempting to statically link the operating
# system itself.  Darwin has no supported static system runtime; private
# dependencies are still selected explicitly as archives by the build recipes.
function(vitasdk_get_host_static_flags system_name out_c out_cxx out_link)
    set(c_flags)
    set(cxx_flags)
    set(link_flags)

    if(system_name STREQUAL "Linux")
        set(c_flags -static-libgcc)
        set(cxx_flags -static-libgcc -static-libstdc++)
        set(link_flags -static-libgcc -static-libstdc++)
    elseif(system_name STREQUAL "Windows")
        set(c_flags -static-libgcc)
        set(cxx_flags -static -static-libgcc -static-libstdc++)
        set(link_flags -static -static-libgcc -static-libstdc++)
    endif()

    set(${out_c} "${c_flags}" PARENT_SCOPE)
    set(${out_cxx} "${cxx_flags}" PARENT_SCOPE)
    set(${out_link} "${link_flags}" PARENT_SCOPE)
endfunction()

function(vitasdk_append_flags variable_name)
    if(NOT ARGN)
        return()
    endif()

    string(JOIN " " appended_flags ${ARGN})
    if(DEFINED ${variable_name} AND NOT "${${variable_name}}" STREQUAL "")
        set(result "${${variable_name}} ${appended_flags}")
    else()
        set(result "${appended_flags}")
    endif()
    set(${variable_name} "${result}" PARENT_SCOPE)
endfunction()
