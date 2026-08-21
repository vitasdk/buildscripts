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
        # This reaches every link that goes straight to the compiler, which is
        # all of them but binutils'; for those see
        # vitasdk_get_libtool_static_flag below.
        set(c_flags -static-libgcc)
        set(cxx_flags -static -static-libgcc -static-libstdc++)
        set(link_flags -static -static-libgcc -static-libstdc++)
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

# Binutils links its programs through libtool, and libtool in link mode drops a
# plain -static whenever the compiler has a PIC flag -- every gcc on Linux has
# one -- so those programs came out needing libc.so while the host claimed to be
# static.  --static the compiler reads as -static and libtool's case does not
# match, so it arrives intact.  (-all-static is the flag libtool honours, but the
# compiler rejects it and configure dies on its own link test; -static-pie clears
# libtool and then fails because the musl toolchain is not default-PIE.)
#
# Only for projects whose programs libtool links: passed everywhere it would
# also reach gcc's lto-plugin, which is a shared library and cannot be linked
# statically.  That plugin stays unloadable on a fully static host either way --
# musl answers dlopen with "Dynamic loading not supported" -- but it must still
# build.
function(vitasdk_get_libtool_static_flag out_flag)
    if(VITASDK_FULLY_STATIC)
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
