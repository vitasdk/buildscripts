#
# Copyright(c) 2016 codestation
# Distributed under the MIT License (http://opensource.org/licenses/MIT)
#

# A host is called two things: the triplet its cross compiler answers to, and
# the name it publishes under. Keeping them apart is what lets a host be
# published under a name it was not built for, which is silent -- the
# artifacts are well formed, they just belong to another machine.

include_guard(GLOBAL)

# The name a host triplet publishes under. The same everywhere except
# FreeBSD, whose cross compiler carries a release number (x86_64-unknown-
# freebsd14-gcc) that its published name does not.
function(vitasdk_published_host_name triplet out_name)
    string(REGEX REPLACE "^(.*-unknown-freebsd)[0-9]+$" "\\1" name "${triplet}")
    set(${out_name} "${name}" PARENT_SCOPE)
endfunction()

# arm64 and aarch64 name one machine: Apple writes the first, config.sub the
# second, and both reach here depending on who was asked.
function(vitasdk_canonical_host_name name out_name)
    string(REGEX REPLACE "^arm64-" "aarch64-" canonical "${name}")
    set(${out_name} "${canonical}" PARENT_SCOPE)
endfunction()

# Fail unless published is the name triplet is entitled to publish under.
function(vitasdk_check_published_host_name published triplet)
    vitasdk_published_host_name("${triplet}" expected)
    vitasdk_canonical_host_name("${expected}" expected_canonical)
    vitasdk_canonical_host_name("${published}" published_canonical)
    if(published_canonical STREQUAL expected_canonical)
        return()
    endif()
    message(FATAL_ERROR
        "this build publishes as ${published} but its toolchain builds "
        "${triplet}. Either it is missing the toolchain file that would make "
        "it cross-compile, or VITASDK_HOST_NAME names the wrong host.")
endfunction()
