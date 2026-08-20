#
# Copyright(c) 2016 codestation
# Distributed under the MIT License (http://opensource.org/licenses/MIT)
#

# The producer / consumer partition of an installed SDK.
#
# Stage 1 builds every artifact that is target code -- host independent by
# construction -- and every other host imports it instead of building it
# again. This file is the manifest of that cut.
#
# The cut runs through files, not directories: <triple>/bin holds the host
# binutils, and lib/gcc/<triple>/<version> mixes the compiler proper (cc1,
# cc1plus, lto1, collect2) with target objects (libgcc.a and the crt files).
# Copying either directory whole drags stage-1 host binaries into the SDK of
# a different host.

include_guard(GLOBAL)

# Subdirectories of <prefix>/<triple> that hold host binaries. binutils
# installs its own copies there for every host, under host-specific names
# (ld vs ld.exe), so an imported one is never overwritten -- it just ships.
function(vitasdk_sysroot_host_subdirectories out_var)
    set(${out_var} bin sbin PARENT_SCOPE)
endfunction()

# Target artifacts under lib/gcc/<triple>/<version>. Everything else in that
# directory is the compiler proper and is built by each host through all-gcc.
function(vitasdk_sysroot_gcc_target_files out_required out_optional)
    set(${out_required} libgcc.a crtbegin.o crtend.o crti.o crtn.o PARENT_SCOPE)
    set(${out_optional} libgcov.a crtfastmath.o PARENT_SCOPE)
endfunction()

# Host independent data outside the sysroot: the NID database consumed by
# vita-libs-gen, plus the samples and the gcc pretty-printers.
function(vitasdk_sysroot_data_directories triple out_var)
    set(${out_var} share/vita-headers share/gcc-${triple} PARENT_SCOPE)
endfunction()

# Provenance travels with the target half: the commit ids it names are the
# ones that produced these artifacts, and no consumer can regenerate them.
function(vitasdk_sysroot_data_files out_var)
    set(${out_var} version_info.txt PARENT_SCOPE)
endfunction()

# Copy the target half of an SDK from one tree to another. The producer
# calls it to lift the sysroot out of its build prefix, a consumer calls it
# to lay a stage-1 sysroot into its own; it is the same set of files either
# way, which is the point of having one manifest.
function(vitasdk_copy_sysroot source destination triple gcc_version)
    set(stage1_dir "${source}")
    set(prefix "${destination}")
    set(sysroot "${stage1_dir}/${triple}")
    if(NOT IS_DIRECTORY "${sysroot}")
        message(FATAL_ERROR "SDK has no ${triple} sysroot: ${sysroot}")
    endif()

    vitasdk_sysroot_host_subdirectories(host_subdirectories)
    file(GLOB sysroot_entries RELATIVE "${sysroot}" "${sysroot}/*")
    foreach(entry IN LISTS sysroot_entries)
        if(entry IN_LIST host_subdirectories)
            message(STATUS "Skipping host directory ${triple}/${entry}")
            continue()
        endif()
        file(COPY "${sysroot}/${entry}" DESTINATION "${prefix}/${triple}")
    endforeach()

    set(gcc_source "${stage1_dir}/lib/gcc/${triple}/${gcc_version}")
    set(gcc_destination "${prefix}/lib/gcc/${triple}/${gcc_version}")
    vitasdk_sysroot_gcc_target_files(required_files optional_files)
    foreach(target_file IN LISTS required_files)
        if(NOT EXISTS "${gcc_source}/${target_file}")
            message(FATAL_ERROR
                "SDK is missing the target object ${target_file} in "
                "${gcc_source}; it cannot seed a consumer build")
        endif()
        file(COPY "${gcc_source}/${target_file}" DESTINATION "${gcc_destination}")
    endforeach()
    foreach(target_file IN LISTS optional_files)
        if(EXISTS "${gcc_source}/${target_file}")
            file(COPY "${gcc_source}/${target_file}" DESTINATION "${gcc_destination}")
        endif()
    endforeach()

    vitasdk_sysroot_data_directories("${triple}" data_directories)
    foreach(directory IN LISTS data_directories)
        if(NOT IS_DIRECTORY "${stage1_dir}/${directory}")
            message(FATAL_ERROR "Source SDK has no ${directory} directory")
        endif()
        get_filename_component(parent "${prefix}/${directory}" DIRECTORY)
        file(COPY "${stage1_dir}/${directory}" DESTINATION "${parent}")
    endforeach()

    vitasdk_sysroot_data_files(data_files)
    foreach(data_file IN LISTS data_files)
        if(NOT EXISTS "${stage1_dir}/${data_file}")
            message(FATAL_ERROR
                "Source SDK has no ${data_file}; refusing to move a sysroot "
                "without provenance")
        endif()
        get_filename_component(parent "${prefix}/${data_file}" DIRECTORY)
        file(COPY "${stage1_dir}/${data_file}" DESTINATION "${parent}")
    endforeach()
endfunction()
