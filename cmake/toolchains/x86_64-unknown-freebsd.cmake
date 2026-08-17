# CMake toolchain for cross compiling the SDK host binaries to x86_64
# FreeBSD from a Linux build machine. Expects the environment prepared by
# scripts/setup-freebsd-cross.sh (clang wrappers named after the triplet
# plus an extracted base-system sysroot) with its bin directory in PATH.
# The FreeBSD major version is part of the triplet; override
# VITASDK_FREEBSD_TRIPLET if you target a different release.

set(CMAKE_SYSTEM_NAME FreeBSD)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

set(VITASDK_FREEBSD_TRIPLET x86_64-unknown-freebsd14 CACHE STRING
    "Triplet of the FreeBSD cross wrappers in PATH")

set(CMAKE_C_COMPILER ${VITASDK_FREEBSD_TRIPLET}-gcc)
set(CMAKE_CXX_COMPILER ${VITASDK_FREEBSD_TRIPLET}-g++)

set(VITASDK_HOST_TRIPLET ${VITASDK_FREEBSD_TRIPLET} CACHE STRING "" FORCE)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
