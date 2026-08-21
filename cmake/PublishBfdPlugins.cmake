# Put GCC's LTO plugin where binutils looks for plugins.
#
# The plugin is one file with two owners: gcc builds it, and ld, ar, nm and
# ranlib load it. gcc knows where it put it and passes -plugin on the link;
# the binutils tools do not, and scan <prefix>/lib/bfd-plugins instead. Without
# a copy there, `ar rcs lib.a foo.o` on an object compiled with -flto fails
# with "plugin needed to handle lto object" -- which is what a plain Makefile
# does. Every distribution ships this copy; we were not.
#
# A copy rather than a symlink: the SDK is shipped as a tarball that is
# unpacked on the host it targets, and a symlink does not survive that on
# Windows.

if(NOT DEFINED SDK_DIR OR NOT DEFINED TARGET_TRIPLE OR NOT DEFINED GCC_VERSION)
    message(FATAL_ERROR "SDK_DIR, TARGET_TRIPLE and GCC_VERSION are required")
endif()

set(gcc_lib_dir "${SDK_DIR}/lib/gcc/${TARGET_TRIPLE}/${GCC_VERSION}")
file(GLOB plugins
    "${gcc_lib_dir}/liblto_plugin.so"
    "${gcc_lib_dir}/liblto_plugin.dll"
    "${gcc_lib_dir}/liblto_plugin.dylib")

if(NOT plugins)
    # Not a warning: this is how the SDK loses LTO without anyone noticing.
    # A -static that reaches gcc's build tells libtool to skip the shared
    # flavour of the plugin; gcc's configure then finds no liblto_plugin.la,
    # records that this host has no plugin, and from then on -flto links
    # without one -- it still optimises, but nothing is ever removed and
    # static archives never take part. The SDK builds green and ships worse
    # code. Fail here instead, while there is something to read.
    message(FATAL_ERROR
        "no loadable LTO plugin in ${gcc_lib_dir}\n"
        "  gcc built only the static flavour, so its driver was configured "
        "without plugin support.\n"
        "  Check that no -static reaches gcc's LDFLAGS "
        "(see cmake/StaticPolicy.cmake).")
endif()

file(MAKE_DIRECTORY "${SDK_DIR}/lib/bfd-plugins")
foreach(plugin ${plugins})
    get_filename_component(plugin_name "${plugin}" NAME)
    file(COPY "${plugin}" DESTINATION "${SDK_DIR}/lib/bfd-plugins")
    message(STATUS "Published ${plugin_name} to lib/bfd-plugins")
endforeach()

# mingw builds an import library beside the DLL. Nothing links against a
# plugin -- it is opened by name at run time -- so it is dead weight, and it
# sits in the target library tree where ValidateStaticSdk.cmake forbids import
# archives. Drop it rather than write it an exception.
file(GLOB import_libraries "${gcc_lib_dir}/liblto_plugin*.dll.a")
foreach(import_library ${import_libraries})
    file(REMOVE "${import_library}")
    get_filename_component(import_name "${import_library}" NAME)
    message(STATUS "Removed ${import_name}, an import library for a plugin")
endforeach()
