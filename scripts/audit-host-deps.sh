#!/usr/bin/env sh
set -eu

: "${VITASDK:?set VITASDK to the SDK installation directory}"

host_system=${VITASDK_HOST_SYSTEM_NAME:-$(uname -s)}
objdump_command=${VITASDK_OBJDUMP:-objdump}

fail_dependency() {
    binary=$1
    dependency=$2
    echo "unexpected dynamic host dependency: $binary -> $dependency" >&2
    exit 1
}

# One reader for every ELF host; what differs between them is only which
# sonames belong to the system.  linux_system_dependency and its FreeBSD
# counterpart answer that, and audit_elf is told which to ask.
linux_system_dependency() {
    case "$1" in
        ld-linux*.so.*|ld-musl-*.so.*|libc.so.*|libc.musl-*.so.*|\
        libm.so.*|libpthread.so.*|libdl.so.*|librt.so.*|libutil.so.*|\
        libresolv.so.*)
            return 0
            ;;
    esac
    return 1
}

# The FreeBSD base system, and nothing else.  A cross-built SDK links against
# the C and C++ runtimes that ship with the operating system it runs on --
# measured on a complete build: libc.so.7, libm.so.5, libgcc_s.so.1,
# libc++.so.1, libcxxrt.so.1 -- while every private library it uses is an
# archive.  Anything outside this list is one we shipped and should not have.
freebsd_system_dependency() {
    case "$1" in
        ld-elf.so.*|libc.so.*|libm.so.*|libthr.so.*|libpthread.so.*|\
        libdl.so.*|librt.so.*|libutil.so.*|libexecinfo.so.*|libmd.so.*|\
        libgcc_s.so.*|libc++.so.*|libcxxrt.so.*|libstdc++.so.*|\
        libncurses*.so.*|libtinfo*.so.*)
            return 0
            ;;
    esac
    return 1
}

audit_elf() {
    if ! command -v "$objdump_command" >/dev/null 2>&1; then
        echo "missing ELF dependency inspector: $objdump_command" >&2
        exit 2
    fi

    find "$VITASDK" -type f -print | while IFS= read -r binary; do
        # Read the dynamic section; never ask the loader. ldd answers by
        # running the program, which cannot work here: these binaries are
        # built for the SDK's host, not for this machine. A musl binary on a
        # glibc runner has no interpreter to load it, and ldd reports its own
        # failure on stdout, where a dependency list is expected --
        #
        #   unexpected dynamic host dependency: .../arm-vita-eabi/bin/nm -> nm:
        #
        # which is ldd naming the file it could not load, not a dependency.
        # A statically linked one is worse: nothing stops it, so it simply
        # runs. objdump is how the Windows audit below has always done it.
        case "$(file -b "$binary" 2>/dev/null)" in
            *ELF*executable*|*ELF*"shared object"*) ;;
            *) continue ;;
        esac

        objdump_output=$("$objdump_command" -p "$binary" 2>/dev/null) || continue
        dependencies=$(printf '%s\n' "$objdump_output" | awk '$1 == "NEEDED" { print $2 }')
        for dependency in $dependencies; do
            "$system_dependency" "$dependency" ||
                fail_dependency "$binary" "$dependency"
        done
    done
}

audit_darwin() {
    find "$VITASDK" -type f -print | while IFS= read -r binary; do
        file_type=$(file -b "$binary" 2>/dev/null || true)
        case "$file_type" in
            *Mach-O*) ;;
            *) continue ;;
        esac

        dependencies=$(otool -L "$binary" 2>/dev/null | sed '1d' || true)
        [ -n "$dependencies" ] || continue

        printf '%s\n' "$dependencies" | while IFS= read -r dependency_line; do
            dependency=$(printf '%s\n' "$dependency_line" | awk '{ print $1 }')
            [ -n "$dependency" ] || continue
            case "$dependency" in
                /usr/lib/*|/System/Library/*)
                    ;;
                *)
                    fail_dependency "$binary" "$dependency"
                    ;;
            esac
        done
    done
}

audit_windows() {
    if ! command -v "$objdump_command" >/dev/null 2>&1; then
        echo "missing PE dependency inspector: $objdump_command" >&2
        exit 2
    fi

    find "$VITASDK" -type f \( -iname '*.exe' -o -iname '*.dll' \) -print |
    while IFS= read -r binary; do
        case "${binary##*/}" in
            libgcc*.dll|libstdc++*.dll|libwinpthread*.dll|zlib*.dll|libz*.dll|\
            libgmp*.dll|libmpfr*.dll|libmpc*.dll|libisl*.dll|libexpat*.dll|\
            libelf*.dll|libzip*.dll|libyaml*.dll)
                fail_dependency "$binary" "private DLL shipped with SDK"
                ;;
        esac

        if ! objdump_output=$("$objdump_command" -p "$binary" 2>/dev/null); then
            echo "unable to inspect PE dependencies: $binary" >&2
            exit 1
        fi
        dependencies=$(printf '%s\n' "$objdump_output" |
            awk 'toupper($0) ~ /DLL NAME:/ { print $3 }')
        for dependency in $dependencies; do
            normalized=$(printf '%s' "$dependency" | tr '[:lower:]' '[:upper:]')
            case "$normalized" in
                API-MS-WIN-*.DLL|EXT-MS-WIN-*.DLL|KERNEL32.DLL|USER32.DLL|\
                ADVAPI32.DLL|SHELL32.DLL|OLE32.DLL|OLEAUT32.DLL|WS2_32.DLL|\
                RPCRT4.DLL|SHLWAPI.DLL|VERSION.DLL|WINMM.DLL|PSAPI.DLL|\
                BCRYPT.DLL|NTDLL.DLL|UCRTBASE.DLL|SECHOST.DLL|MSVCRT.DLL|\
                COMDLG32.DLL|COMCTL32.DLL|GDI32.DLL|IMM32.DLL|SETUPAPI.DLL|\
                IPHLPAPI.DLL|CRYPT32.DLL|DBGHELP.DLL|NETAPI32.DLL|\
                MSYS-2.0.DLL)
                    ;;
                *)
                    fail_dependency "$binary" "$dependency"
                    ;;
            esac
        done
    done
}

case "$host_system" in
    Linux*) system_dependency=linux_system_dependency; audit_elf ;;
    FreeBSD*) system_dependency=freebsd_system_dependency; audit_elf ;;
    Darwin*) audit_darwin ;;
    Windows*|MINGW*|MSYS*|CYGWIN*) audit_windows ;;
    *)
        echo "unsupported host for dependency audit: $host_system" >&2
        exit 2
        ;;
esac

echo "Host dependency audit passed"
