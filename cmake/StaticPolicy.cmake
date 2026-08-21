include_guard(GLOBAL)

# Keep host tools portable without attempting to statically link the operating
# system itself.  Darwin has no supported static system runtime; private
# dependencies are still selected explicitly as archives by the build recipes.
function(vitasdk_get_host_static_flags system_name out_c out_cxx out_link)
    set(c_flags)
    set(cxx_flags)
    set(link_flags)

    if(system_name STREQUAL "Linux" AND VITASDK_FULLY_STATIC)
        # musl hosts: link the whole binary statically so the resulting SDK
        # runs unmodified on Alpine and on any glibc distribution.
        #
        # Spelled --static, which the compiler takes as -static and libtool
        # does not take at all.  In link mode libtool drops a plain -static
        # whenever the compiler has a PIC flag, which every gcc on Linux has,
        # so binutils linked its programs against musl dynamically no matter
        # what this file asked for.  -all-static is the flag libtool honours,
        # but the compiler rejects it and every configure test dies; -static-pie
        # needs a -fPIE rebuild of everything.  This spelling reaches the
        # compiler through both paths untouched, and audit-host-deps.sh is
        # what notices should a libtool ever learn it.
        set(c_flags -static-libgcc)
        set(cxx_flags --static -static-libgcc -static-libstdc++)
        set(link_flags --static -static-libgcc -static-libstdc++)
    elseif(system_name STREQUAL "Linux")
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
