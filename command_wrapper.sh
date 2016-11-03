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

[[ ! -z ${_CFLAGS} ]] && export CFLAGS=${_CFLAGS}
[[ ! -z ${_CXXFLAGS} ]] && export CXXFLAGS=${_CXXFLAGS}
[[ ! -z ${_CPPFLAGS} ]] && export CPPFLAGS=${_CPPFLAGS}
[[ ! -z ${_LDFLAGS} ]] && export LDFLAGS=${_LDFLAGS}

unset _CFLAGS
unset _CXXFLAGS
unset _CPPFLAGS
unset _LDFLAGS

export CONFIG_SITE=

COMMAND_NAME="$1"

shift

${COMMAND_NAME} "$@"
