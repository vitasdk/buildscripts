# CMake toolchain for cross compiling the SDK host binaries to x86_64 macOS
# through osxcross (https://github.com/tpoechtrager/osxcross).
#
# osxcross requires a macOS SDK extracted from Xcode; Apple's license only
# allows using it on Apple hardware unless you accept the risk, which is why
# CI keeps native macOS runners as the default and this file exists for
# environments where osxcross is already set up. Expects the osxcross bin
# directory in PATH and OSXCROSS_TARGET_TRIPLE (e.g. aarch64-apple-darwin23)
# exported, or adjust the compiler names below.

set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_PROCESSOR arm64)

if(DEFINED ENV{OSXCROSS_TARGET_TRIPLE})
    set(CMAKE_C_COMPILER $ENV{OSXCROSS_TARGET_TRIPLE}-clang)
    set(CMAKE_CXX_COMPILER $ENV{OSXCROSS_TARGET_TRIPLE}-clang++)
else()
    set(CMAKE_C_COMPILER oa64-clang)
    set(CMAKE_CXX_COMPILER oa64-clang++)
endif()

set(VITASDK_HOST_TRIPLET aarch64-apple-darwin CACHE STRING "" FORCE)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
