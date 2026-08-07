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

audit_linux() {
    find "$VITASDK" -type f -print | while IFS= read -r binary; do
        dependencies=$(ldd "$binary" 2>/dev/null || true)
        [ -n "$dependencies" ] || continue

        for dependency in $(printf '%s\n' "$dependencies" | awk '
            /=>/ { print $1; next }
            /^[[:space:]]*\// { print $1; next }
            /linux-vdso/ { print $1 }
        '); do
            dependency=${dependency##*/}
            case "$dependency" in
                linux-vdso.so.*|ld-linux*.so.*|ld-musl-*.so.*|libc.so.*|libc.musl-*.so.*|\
                libm.so.*|libpthread.so.*|libdl.so.*|librt.so.*|libutil.so.*|\
                libresolv.so.*)
                    ;;
                *)
                    fail_dependency "$binary" "$dependency"
                    ;;
            esac
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
                IPHLPAPI.DLL|CRYPT32.DLL|DBGHELP.DLL)
                    ;;
                *)
                    fail_dependency "$binary" "$dependency"
                    ;;
            esac
        done
    done
}

case "$host_system" in
    Linux*) audit_linux ;;
    Darwin*) audit_darwin ;;
    Windows*|MINGW*|MSYS*|CYGWIN*) audit_windows ;;
    *)
        echo "unsupported host for dependency audit: $host_system" >&2
        exit 2
        ;;
esac

echo "Host dependency audit passed"
