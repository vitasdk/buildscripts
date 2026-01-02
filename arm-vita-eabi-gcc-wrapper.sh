#!/bin/sh
# Wrapper for arm-vita-eabi-gcc (clang) to add Vita-specific libraries
# This replicates the LIB_SPEC behavior from GCC patch

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Determine if we are running as C++ compiler
NAME=$(basename "$0")
IS_CXX=0
case "$NAME" in
    *g++*|*c++*)
        CLANG="${SCRIPT_DIR}/clang++"
        IS_CXX=1
        ;;
    *)
        CLANG="${SCRIPT_DIR}/clang"
        ;;
esac

# Default Vita libraries (from LIB_SPEC in gcc.cc patch)
VITA_LIBS="-lSceRtc_stub -lSceSysmem_stub -lSceKernelThreadMgr_stub -lSceKernelModulemgr_stub -lSceIofilemgr_stub -lSceProcessmgr_stub -lSceLibKernel_stub -lSceNet_stub -lSceNetCtl_stub -lSceSysmodule_stub"

# Check if we're linking (not just compiling)
LINKING=1
SHARED=0
for arg in "$@"; do
    case "$arg" in
        -c|-E|-S)
            LINKING=0
            ;;
        -shared)
            SHARED=1
            ;;
    esac
done

# Execute clang with config file
if [ $LINKING -eq 1 ]; then
    # When linking, add all necessary libraries
    # Always include pthread (newlib requires it)
    # Use -Wl,--whole-archive for pthread to ensure all symbols are available
    
    if [ $SHARED -eq 0 ]; then
        # For executables, include standard libraries and Vita stubs
        if [ $IS_CXX -eq 1 ]; then
            # C++ executables need libc++ or libstdc++
            # Clang will automatically add -lc++ but we need to ensure proper order
            exec "${CLANG}" --config "${SCRIPT_DIR}/arm-vita-eabi.cfg" "$@" \
                -Wl,--whole-archive -lpthread -Wl,--no-whole-archive \
                -lc -lgloss -lm ${VITA_LIBS}
        else
            # C executables
            exec "${CLANG}" --config "${SCRIPT_DIR}/arm-vita-eabi.cfg" "$@" \
                -Wl,--whole-archive -lpthread -Wl,--no-whole-archive \
                -lc -lgloss -lm ${VITA_LIBS}
        fi
    else
        # For shared libraries, minimal linking
        exec "${CLANG}" --config "${SCRIPT_DIR}/arm-vita-eabi.cfg" "$@"
    fi
else
    # Just compile, no libraries needed
    # Config must be first so architecture flags are applied
    exec "${CLANG}" --config "${SCRIPT_DIR}/arm-vita-eabi.cfg" "$@"
fi
