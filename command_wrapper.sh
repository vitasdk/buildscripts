#!/usr/bin/env bash

# According to the CMake folks, this is the way to do things.
# http://www.cmake.org/pipermail/cmake/2010-April/036566.html

trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"   # remove leading whitespace characters
    var="${var%"${var##*[![:space:]]}"}"   # remove trailing whitespace characters
    echo -n "$var"
}

: "${CFLAGS:=}"
: "${CXXFLAGS:=}"
: "${CPPFLAGS:=}"
: "${LDFLAGS:=}"

_CFLAGS=$(trim "${_CFLAGS} ${CFLAGS}")
_CXXFLAGS=$(trim "${_CXXFLAGS} ${CXXFLAGS}")
_CPPFLAGS=$(trim "${_CPPFLAGS} ${CPPFLAGS}")
_LDFLAGS=$(trim "${_LDFLAGS} ${LDFLAGS}")

[[ -n "${_CFLAGS}" ]] && export CFLAGS="${_CFLAGS}"
[[ -n "${_CXXFLAGS}" ]] && export CXXFLAGS="${_CXXFLAGS}"
[[ -n "${_CPPFLAGS}" ]] && export CPPFLAGS="${_CPPFLAGS}"
[[ -n "${_LDFLAGS}" ]] && export LDFLAGS="${_LDFLAGS}"

unset _CFLAGS
unset _CXXFLAGS
unset _CPPFLAGS
unset _LDFLAGS

export CONFIG_SITE=

if (( $# == 0 )); then
    echo "command_wrapper.sh: missing command" >&2
    exit 64
fi

COMMAND_NAME="$1"
shift

exec "$COMMAND_NAME" "$@"
