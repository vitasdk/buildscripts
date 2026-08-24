# CMake toolchain for building the SDK host binaries for x86_64 macOS on an
# Apple silicon build machine, through the system Xcode toolchain with
# -arch x86_64. Apple's SDK licence keeps it on Apple hardware, so this is how
# an x86_64 SDK is produced without osxcross: same runner, same SDK, other
# architecture. Expects the wrappers from scripts/setup-macos-cross.sh in PATH.
#
# On a Linux build machine with osxcross already set up, override the two
# compiler variables with the osxcross names (o64-clang / o64-clang++, or
# $OSXCROSS_TARGET_TRIPLE-clang); nothing else in this file changes.

set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

set(CMAKE_C_COMPILER x86_64-apple-darwin-gcc)
set(CMAKE_CXX_COMPILER x86_64-apple-darwin-g++)

set(VITASDK_HOST_TRIPLET x86_64-apple-darwin CACHE STRING "" FORCE)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
