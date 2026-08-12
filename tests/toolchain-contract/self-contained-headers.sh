#!/usr/bin/env sh
# Every public header must compile on its own.
#
# A header that uses a type it never declares still compiles for most people,
# because whatever they included first happened to provide it. That is not a
# working header, it is a header with an undeclared dependency and a lucky
# include order.
#
# The case this exists for: pthread-embedded's <semaphore.h> declared
# sem_open() with mode_t and sem_timedwait() with struct timespec while
# including nothing at all. It built for years because newlib's <stdio.h>
# pulled in <sys/types.h>, and stopped when upstream narrowed that in 2022
# (357d7fcc6, released in newlib 4.3.0). Nothing about the header changed; the
# accident it relied on did.

set -eu

: "${VITASDK:?set VITASDK to the VitaSDK installation directory}"

CC="${VITASDK}/bin/arm-vita-eabi-gcc"
include_dir="${VITASDK}/arm-vita-eabi/include"

[ -x "${CC}" ] || { echo "missing tool: ${CC}" >&2; exit 1; }

workdir=$(mktemp -d "${TMPDIR:-/tmp}/vita-headers.XXXXXX")
trap 'rm -rf "${workdir}"' EXIT HUP INT TERM

# Headers shipped by VitaSDK's own components, at the top of the include
# directory. The psp2 trees are generated and are checked by vita-headers.
headers=$(cd "${include_dir}" && ls *.h 2>/dev/null || true)
[ -n "${headers}" ] || { echo "no headers found in ${include_dir}" >&2; exit 1; }

# Headers that come from newlib and do not compile alone today. They are
# listed rather than skipped silently, and the list is checked in both
# directions: an unlisted header that fails is a regression, and a listed one
# that starts passing is a stale exception. Neither is allowed to rot.
#
#   regdef.h, regex.h   use types they never declare
#   termios.h, utmp.h   include sys/ headers this target does not ship
#   threads.h           includes machine/_threads.h, absent for this target
#   utime.h             sys/utime.h uses time_t without declaring it
known_broken="regdef.h regex.h termios.h threads.h utime.h utmp.h"

is_known_broken()
{
    for known in ${known_broken}; do
        [ "$1" = "${known}" ] && return 0
    done
    return 1
}

failed=0
checked=0
fixed=""
for header in ${headers}; do
    printf '#include <%s>\nint main(void) { return 0; }\n' "${header}" \
        > "${workdir}/tu.c"
    if output=$("${CC}" -std=gnu11 -Wall -Werror -fsyntax-only \
            "${workdir}/tu.c" 2>&1); then
        checked=$((checked + 1))
        if is_known_broken "${header}"; then
            fixed="${fixed} ${header}"
        fi
    elif is_known_broken "${header}"; then
        checked=$((checked + 1))
    else
        failed=$((failed + 1))
        echo "<${header}> does not compile on its own:" >&2
        printf '%s\n' "${output}" | head -5 >&2
    fi
done

if [ "${failed}" -ne 0 ]; then
    echo "${failed} header(s) are not self contained" >&2
    exit 1
fi

if [ -n "${fixed}" ]; then
    echo "these are listed as known broken but now compile:${fixed}" >&2
    echo "remove them from known_broken" >&2
    exit 1
fi

echo "self-contained headers OK (${checked} checked)"
