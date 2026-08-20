# CMake toolchain for cross compiling the SDK host binaries to aarch64 musl.
# The result is a fully static SDK that runs on Alpine and on any glibc
# distribution alike. Expects a musl cross compiler in PATH, e.g. the
# release from https://github.com/cross-tools/musl-cross or one built with
# richfelker/musl-cross-make. The published toolchains name the host with a
# vendor field (aarch64-unknown-linux-musl); the SDK does not, and CI aliases
# the tools so both names resolve.

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(CMAKE_C_COMPILER aarch64-linux-musl-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-musl-g++)

# The build machine is usually glibc, so the /etc/alpine-release heuristic in
# GetTriplet.cmake cannot see this; pin the triplet explicitly.
set(VITASDK_HOST_TRIPLET aarch64-linux-musl CACHE STRING "" FORCE)
# Link host binaries with -static (see StaticPolicy.cmake).
set(VITASDK_FULLY_STATIC ON CACHE BOOL "" FORCE)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
