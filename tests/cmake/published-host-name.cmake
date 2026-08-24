cmake_minimum_required(VERSION 3.16)

# A host is called two things: the triplet its cross compiler answers to, and
# the name it publishes under. They are the same everywhere except FreeBSD,
# whose compiler carries a release number its published name does not -- and
# mixing them up published a bundle nobody could match to a host.

function(published_name_of triplet out)
    string(REGEX REPLACE "^(.*-unknown-freebsd)[0-9]+$" "\\1" name "${triplet}")
    set(${out} "${name}" PARENT_SCOPE)
endfunction()

function(assert_published triplet expected)
    published_name_of("${triplet}" actual)
    if(NOT "${actual}" STREQUAL "${expected}")
        message(FATAL_ERROR
            "${triplet} publishes as '${actual}', expected '${expected}'")
    endif()
endfunction()

assert_published(x86_64-unknown-freebsd14 x86_64-unknown-freebsd)
assert_published(aarch64-unknown-freebsd14 aarch64-unknown-freebsd)

# Every other host publishes under the triplet it builds with.
foreach(triplet x86_64-linux-gnu aarch64-linux-gnu x86_64-linux-musl
        aarch64-linux-musl arm64-apple-darwin x86_64-apple-darwin
        x86_64-w64-mingw32 i686-w64-mingw32)
    assert_published("${triplet}" "${triplet}")
endforeach()

message(STATUS "published host name checks passed")
