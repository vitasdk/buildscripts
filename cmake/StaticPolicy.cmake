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
        # No plain -static here. In library mode libtool reads it as "do not
        # build the shared flavour", which silently cost this host GCC's LTO
        # plugin -- a DLL that Windows can load perfectly well. The host
        # programs get it through vitasdk_get_libtool_static_flag instead.
        set(c_flags -static-libgcc)
        set(cxx_flags -static-libgcc -static-libstdc++)
        set(link_flags -static-libgcc -static-libstdc++)
    elseif(system_name STREQUAL "Darwin")
        # ld64 looks for a dylib in every search path before it considers a
        # static library in any of them, so the dependencies built here --
        # static only -- lose to a Homebrew copy of the same name. That only
        # bites on Intel, where Homebrew's /usr/local is an implicit search
        # path; searching each directory for either kind settles it.
        set(link_flags -Wl,-search_paths_first)
    endif()

    set(${out_c} "${c_flags}" PARENT_SCOPE)
    set(${out_cxx} "${cxx_flags}" PARENT_SCOPE)
    set(${out_link} "${link_flags}" PARENT_SCOPE)
endfunction()

# Windows ships host programs that depend on nothing but the system DLLs, which
# takes a -static.  It cannot go in the flags above: binutils and gdb link their
# programs through libtool, and libtool in library mode reads -static as "do not
# build the shared flavour", which is how this host quietly lost GCC's LTO
# plugin -- a DLL that Windows loads perfectly well.  Spelled --static it
# reaches the compiler all the same, since gcc reads it as -static, while
# libtool's case statement does not match it, so gcc's build still produces the
# plugin.
#
# Given only to the projects whose programs libtool links, which is binutils and
# gdb.  gcc links its own programs directly and takes the flags above.
function(vitasdk_get_libtool_static_flag system_name out_flag)
    if(system_name STREQUAL "Windows")
        set(${out_flag} "--static" PARENT_SCOPE)
    else()
        set(${out_flag} "" PARENT_SCOPE)
    endif()
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
