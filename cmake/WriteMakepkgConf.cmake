#
# Stamps the world's CARCH into the makepkg.conf shipped inside the SDK.
# vita-makepkg's own makepkg.conf.sample always says CARCH="vita": this is
# the one place that turns it into the world the core was actually built for.
#

if(NOT DEFINED INPUT OR NOT DEFINED OUTPUT OR NOT DEFINED WORLD_ARCH)
    message(FATAL_ERROR "INPUT, OUTPUT and WORLD_ARCH are required")
endif()

file(READ "${INPUT}" contents)
string(REGEX REPLACE "\nCARCH=\"[^\"]*\"\n" "\nCARCH=\"${WORLD_ARCH}\"\n"
    contents "${contents}")

get_filename_component(output_directory "${OUTPUT}" DIRECTORY)
file(MAKE_DIRECTORY "${output_directory}")
set(temporary "${OUTPUT}.tmp")
file(WRITE "${temporary}" "${contents}")
file(RENAME "${temporary}" "${OUTPUT}")
