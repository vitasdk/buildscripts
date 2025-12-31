#!/bin/sh
# Wrapper for arm-vita-eabi-gcc (clang) to add Vita-specific libraries
# This replicates the LIB_SPEC behavior from GCC patch

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Determine if we are running as C++ compiler
NAME=$(basename "$0")
case "$NAME" in
    *g++*|*c++*)
        CLANG="${SCRIPT_DIR}/../arm-vita-eabi/bin/clang++"
        ;;
    *)
        CLANG="${SCRIPT_DIR}/../arm-vita-eabi/bin/clang"
        ;;
esac

# Default Vita libraries (from LIB_SPEC in gcc.cc patch)
VITA_LIBS="-lSceRtc_stub -lSceSysmem_stub -lSceKernelThreadMgr_stub -lSceKernelModulemgr_stub -lSceIofilemgr_stub -lSceProcessmgr_stub -lSceLibKernel_stub -lSceNet_stub -lSceNetCtl_stub -lSceSysmodule_stub"

# Check if we're linking (not just compiling)
LINKING=1
for arg in "$@"; do
    case "$arg" in
        -c|-E|-S)
            LINKING=0
            break
            ;;
    esac
done

# Execute clang with config file
if [ $LINKING -eq 1 ]; then
    # Add Vita libraries when linking
    # Check if -pthread is in arguments
    PTHREAD_LIBS=""
    for arg in "$@"; do
        case "$arg" in
            -pthread|--pthread)
                PTHREAD_LIBS="--whole-archive -lpthread --no-whole-archive"
                break
                ;;
        esac
    done
    
    exec "${CLANG}" --config "${SCRIPT_DIR}/arm-vita-eabi.cfg" "$@" ${PTHREAD_LIBS} ${VITA_LIBS}
else
    # Just compile, no libraries needed
    exec "${CLANG}" --config "${SCRIPT_DIR}/arm-vita-eabi.cfg" "$@"
fi
