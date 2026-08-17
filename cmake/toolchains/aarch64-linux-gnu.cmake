# CMake toolchain for cross compiling the SDK host binaries to aarch64 glibc
# from an x86_64 Linux build machine (alternative to building natively on an
# arm64 runner). Uses the distribution cross compiler, e.g. the Debian/Ubuntu
# g++-aarch64-linux-gnu package.

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(CMAKE_C_COMPILER aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)

set(VITASDK_HOST_TRIPLET aarch64-linux-gnu CACHE STRING "" FORCE)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
