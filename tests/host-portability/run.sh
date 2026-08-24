#!/bin/sh
# Does a built SDK actually run on this machine, and does it compile?
#
# The audit in scripts/audit-host-deps.sh reads what a binary asks the loader
# for; this runs the binaries instead, on a machine that is not the one that
# built them. That is the only way to check what the README promises of the
# musl hosts -- one SDK that runs on Alpine and on any glibc distribution --
# and it is the check that promise had never had.
#
# Usage: extract an SDK tarball somewhere, point VITASDK at it, and run this:
#
#   tar -xf vitasdk-x86_64-linux-musl-*.tar.bz2 -C /opt
#   VITASDK=/opt/vitasdk tests/host-portability/run.sh
#
# Nothing is installed and nothing is written outside a temporary directory,
# so a bare container is a fair machine to run it on:
#
#   docker run --rm -v /opt/vitasdk:/opt/vitasdk:ro -v "$PWD":/src:ro \
#       alpine:3.20 sh /src/tests/host-portability/run.sh

set -u
: "${VITASDK:?set VITASDK to an extracted SDK}"
[ -x "$VITASDK/bin/arm-vita-eabi-gcc" ] || {
    echo "no SDK at $VITASDK" >&2
    exit 2
}
PATH="$VITASDK/bin:$PATH"
export VITASDK PATH

echo "host: $(uname -m) $(sed -n 's/^PRETTY_NAME=//p' /etc/os-release 2>/dev/null)"

failures=0

# Runs and says something recognisable. Some of these tools print their usage
# and exit non-zero, which still proves the binary loaded on this libc.
speaks() {
    label=$1
    needle=$2
    shift 2
    output=$("$@" 2>&1)
    # 127 is the shell failing to run it at all -- a binary for another libc
    # reads as "not found", and that message carries the program's own name,
    # which would otherwise match the needle and pass.
    if [ $? -eq 127 ]; then
        echo "  FAIL  $label: cannot execute on this host"
        failures=$((failures + 1))
    elif printf '%s' "$output" | grep -q "$needle"; then
        echo "  ok    $label"
    else
        echo "  FAIL  $label: $(printf '%s' "$output" | head -2 | tr '\n' ' ')"
        failures=$((failures + 1))
    fi
}

# nm comes from binutils and run from gdb's simulator: one program from each of
# the two projects whose programs libtool links, which is where a host that only
# claims to be static gives itself away.
speaks "arm-vita-eabi-gcc"  "GNU"             arm-vita-eabi-gcc --version
speaks "arm-vita-eabi-nm"   "GNU"             arm-vita-eabi-nm --version
speaks "arm-vita-eabi-ld"   "GNU"             arm-vita-eabi-ld --version
speaks "arm-vita-eabi-gdb"  "GNU"             arm-vita-eabi-gdb --version
speaks "arm-vita-eabi-run"  "GNU"             arm-vita-eabi-run --version
speaks "vita-elf-create"    "vita-elf-create" vita-elf-create -h
speaks "vita-pack-vpk"      "vita-pack-vpk"   vita-pack-vpk --help
speaks "vdpm"               "VitaSDK"         vdpm --help

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work" || exit 2

printf '#include <stdio.h>\nint main(void){printf("hello\\n");return 0;}\n' > hello.c
if arm-vita-eabi-gcc -O2 hello.c -o hello.elf 2> c.log &&
   arm-vita-eabi-readelf -h hello.elf | grep -q "Machine: *ARM"; then
    echo "  ok    C compiles and links to an ARM ELF"
else
    echo "  FAIL  C: $(head -3 c.log | tr '\n' ' ')"
    failures=$((failures + 1))
fi

printf '#include <string>\n#include <cstdio>\nint main(){std::string s="ok";printf("%%s\\n",s.c_str());}\n' > hello.cc
if arm-vita-eabi-g++ -O2 hello.cc -o hello-cc.elf 2> cxx.log; then
    echo "  ok    C++ compiles and links"
else
    echo "  FAIL  C++: $(head -3 cxx.log | tr '\n' ' ')"
    failures=$((failures + 1))
fi

if [ "$failures" -eq 0 ]; then
    echo "Host portability check passed"
else
    echo "$failures check(s) failed" >&2
fi
exit "$failures"
