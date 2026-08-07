#!/usr/bin/env sh
set -eu

: "${VITASDK:?set VITASDK to the SDK installation directory}"

case "$(uname -s)" in
Linux*)
    for file in "$VITASDK"/bin/*; do
        [ -x "$file" ] || continue
        if ldd "$file" 2>/dev/null | grep -E 'libstdc\+\+|libgcc_s'; then
            echo "unexpected host runtime dependency: $file" >&2
            exit 1
        fi
    done
    ;;
Darwin*)
    for file in "$VITASDK"/bin/*; do
        [ -x "$file" ] || continue
        if otool -L "$file" 2>/dev/null |
            grep -E '/(opt|usr/local)/.*(gmp|mpfr|mpc|isl|zlib|expat)'; then
            echo "unexpected private host dependency: $file" >&2
            exit 1
        fi
    done
    ;;
MINGW*|MSYS*|CYGWIN*)
    for file in "$VITASDK"/bin/*.exe; do
        [ -x "$file" ] || continue
        if objdump -p "$file" 2>/dev/null |
            grep -Ei 'DLL Name:.*(libgcc|libstdc\+\+|libwinpthread)'; then
            echo "unexpected host runtime DLL dependency: $file" >&2
            exit 1
        fi
    done
    ;;
esac
