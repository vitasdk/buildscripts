cmake_minimum_required(VERSION 3.0.2)

project(vitasdk)

find_package(Git REQUIRED)

list(APPEND CMAKE_MODULE_PATH "${PROJECT_SOURCE_DIR}/cmake")

# Use the following gcc version
set(GCC_VERSION 5.4.0)
set(GCC_MD5 4c626ac2a83ef30dfb9260e6f59c2b30)

# installation directory
set(CMAKE_INSTALL_PREFIX ${CMAKE_BINARY_DIR}/vitasdk)
# alias for the installation directory
set(VITASDK ${CMAKE_INSTALL_PREFIX})
# toolchain dependencies
set(DEPS_DIR ${CMAKE_BINARY_DIR}/deps)
# toolchain arch target
set(TARGET_ARCH arm-vita-eabi)
# build date
string(TIMESTAMP BUILD_DATE "%Y-%m-%d_%H-%M-%S")

include(Utils)
include(GetTriplet)
include(ExternalProject)

# identify host and build systems
get_host_triplet(HOST_NATIVE)
get_build_triplet(BUILD_NATIVE)

message(STATUS "Host:   ${HOST_NATIVE}")
message(STATUS "Build:  ${BUILD_NATIVE}")
message(STATUS "Target: ${TARGET_ARCH}")

# load the compiler flags to pass them to the other projects
load_flags(COMPILER_FLAGS)

# macro to build the dependencies required for the vitasdk toolchain/headers
macro(toolchain_deps TOOLCHAIN_DEPS_DIR TOOLCHAIN_INSTALL_DIR TOOLCHAIN_SUFFIX)
    set(extra_macro_args ${ARGN})

    # check if the toolchain file has been passed as optional argument
    list(LENGTH extra_macro_args num_extra_args)
    if (${num_extra_args} GREATER 0)
        list(GET extra_macro_args 0 TOOLCHAIN_FILE)
    endif ()

    if (TOOLCHAIN_FILE)
        set(TOOLCHAIN_HOST --host=${HOST_NATIVE})
        set(TOOLCHAIN_CMAKE_ARGS -DCMAKE_TOOLCHAIN_FILE=${TOOLCHAIN_FILE})
        # workaround for libelf configure (doesn't detect the compiler)
        set(CC_COMPILER "${HOST_NATIVE}-gcc")
    else ()
        set(CC_COMPILER "gcc")
    endif ()

    ExternalProject_Add(binutils${TOOLCHAIN_SUFFIX}
        URL https://ftp.gnu.org/gnu/binutils/binutils-2.27.tar.bz2
        URL_MD5 2869c9bf3e60ee97c74ac2a6bf4e9d68
        PATCH_COMMAND patch -d <SOURCE_DIR> -p3 -t -N < ${PROJECT_SOURCE_DIR}/patches/binutils.patch
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
        ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
        --build=${BUILD_NATIVE}
        ${TOOLCHAIN_HOST}
        --target=${TARGET_ARCH}
        --prefix=${TOOLCHAIN_INSTALL_DIR}
        --with-sysroot=${TOOLCHAIN_INSTALL_DIR}
        --disable-multilib
        --disable-nls
        --disable-shared
        --disable-werror
        --enable-interwork
        --enable-plugins
        BUILD_COMMAND $(MAKE) -j${MAKEJOBS}
        INSTALL_COMMAND $(MAKE) install
        )

    ExternalProject_Add(zlib${TOOLCHAIN_SUFFIX}
        URL http://zlib.net/zlib-1.2.8.tar.gz
        URL_MD5 44d667c142d7cda120332623eab69f40
        CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=${TOOLCHAIN_DEPS_DIR}
        ${TOOLCHAIN_CMAKE_ARGS}
        )

    # rename the zlib static file on windows so matches the other platforms
    if (TOOLCHAIN_FILE AND ${CMAKE_SYSTEM_NAME} STREQUAL "Windows")
        ExternalProject_Add_Step(zlib${TOOLCHAIN_SUFFIX}
            copy_lib
            DEPENDEES install
            COMMAND ${CMAKE_COMMAND} -E copy
            ${TOOLCHAIN_DEPS_DIR}/lib/libzlibstatic.a
            ${TOOLCHAIN_DEPS_DIR}/lib/libz.a
            COMMENT "Copying libzlibstatic to libz"
            )

        set(LIBZIP_CONFIGURE -DCMAKE_C_FLAGS=-DZIP_STATIC)
    endif ()

    # different configurations for the unix/ builds of the toolchain
    if (NOT ${CMAKE_SYSTEM_NAME} STREQUAL "Windows")
        set(VITA_TOOLCHAIN_CMAKE_ARGS -DUSE_BUNDLED_ENDIAN_H=ON)
    else ()
        set(VITA_TOOLCHAIN_CMAKE_ARGS -DZIP_STATIC=ON)
    endif ()

    ExternalProject_Add(libzip${TOOLCHAIN_SUFFIX}
        DEPENDS zlib${TOOLCHAIN_SUFFIX}
        URL https://nih.at/libzip/libzip-1.1.3.tar.gz
        URL_MD5 898f02db185068c8ae45bafe4c5cc81c
        PATCH_COMMAND patch -d <SOURCE_DIR> -p3 -t -N < ${PROJECT_SOURCE_DIR}/patches/libzip.patch
        CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=${TOOLCHAIN_DEPS_DIR}
        ${TOOLCHAIN_CMAKE_ARGS}
        ${LIBZIP_CONFIGURE}
        -DZLIB_INCLUDE_DIR=${TOOLCHAIN_DEPS_DIR}/include
        -DZLIB_LIBRARY=${TOOLCHAIN_DEPS_DIR}/lib/libz.a
        )

    ExternalProject_add(libelf${TOOLCHAIN_SUFFIX}
        URL http://www.mr511.de/software/libelf-0.8.13.tar.gz
        URL_MD5 4136d7b4c04df68b686570afa26988ac
        PATCH_COMMAND patch -d <SOURCE_DIR> -p3 -t -N < ${PROJECT_SOURCE_DIR}/patches/libelf.patch
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env CC=${CC_COMPILER} ${COMPILER_FLAGS}
        ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
        --build=${BUILD_NATIVE}
        ${TOOLCHAIN_HOST}
        --target=${TARGET_ARCH}
        --prefix=${TOOLCHAIN_DEPS_DIR}
        --libdir=${TOOLCHAIN_DEPS_DIR}/lib
        --disable-shared
        --disable-nls
        )

    ExternalProject_add(jansson${TOOLCHAIN_SUFFIX}
        URL http://www.digip.org/jansson/releases/jansson-2.8.tar.bz2
        URL_MD5 592e29db0903d3031ea5a4e5a22fe75c
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
        ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
        --build=${BUILD_NATIVE}
        ${TOOLCHAIN_HOST}
        --target=${TARGET_ARCH}
        --prefix=${TOOLCHAIN_DEPS_DIR}
        --libdir=${TOOLCHAIN_DEPS_DIR}/lib
        --disable-shared
        --enable-static
        )

    ExternalProject_Add(vita-toolchain${TOOLCHAIN_SUFFIX}
        DEPENDS jansson${TOOLCHAIN_SUFFIX} libelf${TOOLCHAIN_SUFFIX} zlib${TOOLCHAIN_SUFFIX} libzip${TOOLCHAIN_SUFFIX}
        GIT_REPOSITORY https://github.com/vitasdk/vita-toolchain
        GIT_TAG master
        CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=${TOOLCHAIN_INSTALL_DIR}
        ${TOOLCHAIN_CMAKE_ARGS}
        ${VITA_TOOLCHAIN_CMAKE_ARGS}
        -DJansson_INCLUDE_DIR=${TOOLCHAIN_DEPS_DIR}/include
        -DJansson_LIBRARY=${TOOLCHAIN_DEPS_DIR}/lib/libjansson.a
        -Dlibelf_INCLUDE_DIR=${TOOLCHAIN_DEPS_DIR}/include
        -Dlibelf_LIBRARY=${TOOLCHAIN_DEPS_DIR}/lib/libelf.a
        -Dzlib_INCLUDE_DIR=${TOOLCHAIN_DEPS_DIR}/include
        -Dzlib_LIBRARY=${TOOLCHAIN_DEPS_DIR}/lib/libz.a
        -Dlibzip_INCLUDE_DIR=${TOOLCHAIN_DEPS_DIR}/include
        -Dlibzip_CONFIG_INCLUDE_DIR=${TOOLCHAIN_DEPS_DIR}/lib/libzip/include
        -Dlibzip_LIBRARY=${TOOLCHAIN_DEPS_DIR}/lib/libzip.a
        -DDEFAULT_JSON=../share/db.json
        BUILD_COMMAND $(MAKE)
        INSTALL_COMMAND $(MAKE) install
        COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/vita-toolchain-version.txt
        )
endmacro()

if (CMAKE_TOOLCHAIN_FILE)
    # get the absolute path of the toolchain file, relative paths doesn't with external projects
    get_filename_component(TOOLCHAIN_FILEPATH "${CMAKE_TOOLCHAIN_FILE}" ABSOLUTE)
    # build a temporal vita-toolchain and binutils to build the vita-headers
    toolchain_deps("${DEPS_DIR}_host" "${CMAKE_BINARY_DIR}/toolchain_host" "_host")
    # build the native vita-toolchain and binutils
    toolchain_deps("${DEPS_DIR}" "${CMAKE_INSTALL_PREFIX}" "" "${TOOLCHAIN_FILEPATH}")

    # set variables needed for the vita headers build step
    set(VITA_LIBS_GEN_COMMAND "${CMAKE_BINARY_DIR}/toolchain_host/bin/vita-libs-gen")
    set(BINUTILS_PREFIX "${CMAKE_BINARY_DIR}/toolchain_host/bin/${TARGET_ARCH}")
    set(VITA_HEADERS_DEPENDS binutils_host vita-toolchain_host)
else ()
    # build the native vita-toolchain and binutils
    toolchain_deps("${DEPS_DIR}" "${CMAKE_INSTALL_PREFIX}" "")

    # set variables needed for the vita-headers build step
    set(VITA_LIBS_GEN_COMMAND "${CMAKE_INSTALL_PREFIX}/bin/vita-libs-gen")
    set(BINUTILS_PREFIX "${CMAKE_INSTALL_PREFIX}/bin/${TARGET_ARCH}")
    set(VITA_HEADERS_DEPENDS binutils vita-toolchain)
endif ()

# tools for cross compilation
list(APPEND TARGET_TOOLS
    AR_FOR_TARGET="${BINUTILS_PREFIX}-ar"
    NM_FOR_TARGET="${BINUTILS_PREFIX}-nm"
    STRIP_FOR_TARGET="${BINUTILS_PREFIX}-strip"
    RANLIB_FOR_TARGET="${BINUTILS_PREFIX}-ranlib"
    CC_FOR_TARGET="${BINUTILS_PREFIX}-gcc"
    GCC_FOR_TARGET="${BINUTILS_PREFIX}-gcc"
    GXX_FOR_TARGET="${BINUTILS_PREFIX}-g++"
    )

# tools for pthread-embedded
list(APPEND PTHREAD_TOOLS
    CC="${BINUTILS_PREFIX}-gcc"
    CXX="${BINUTILS_PREFIX}-g++"
    AR="${BINUTILS_PREFIX}-ar"
    )

# flags for cross compilation
set(CFLAGS_FOR_TARGET "-g -O2 -ffunction-sections -fdata-sections")

set(COMMON_DEPS_CONFIGURE_ARGS
    --build=${BUILD_NATIVE}
    --host=${HOST_NATIVE}
    --prefix=${DEPS_DIR}
    --libdir=${DEPS_DIR}/lib
    )

ExternalProject_add(gmp
    URL https://gmplib.org/download/gmp/gmp-6.1.1.tar.bz2
    URL_MD5 4c175f86e11eb32d8bf9872ca3a8e11d
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env CPPFLAGS=-fexceptions ${COMPILER_FLAGS}
    ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
    ${COMMON_DEPS_CONFIGURE_ARGS}
    --enable-cxx
    --disable-shared
    BUILD_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
    ${PROJECT_SOURCE_DIR}/command_wrapper.sh $(MAKE)
    )

ExternalProject_add(mpfr
    DEPENDS gmp
    URL http://ftp.gnu.org/gnu/mpfr/mpfr-3.1.5.tar.bz2
    URL_MD5 b1d23a55588e3b2a13e3be66bc69fd8d
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
    ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
    ${COMMON_DEPS_CONFIGURE_ARGS}
    --with-gmp=${DEPS_DIR}
    --disable-shared
    )

ExternalProject_add(mpc
    DEPENDS gmp mpfr
    URL http://www.multiprecision.org/mpc/download/mpc-1.0.3.tar.gz
    URL_MD5 d6a1d5f8ddea3abd2cc3e98f58352d26
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
    ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
    ${COMMON_DEPS_CONFIGURE_ARGS}
    --with-gmp=${DEPS_DIR}
    --with-mpfr=${DEPS_DIR}
    --disable-shared
    --disable-nls
    )

ExternalProject_add(isl
    DEPENDS gmp
    URL http://isl.gforge.inria.fr/isl-0.17.1.tar.bz2
    URL_MD5 5184f543a013165e8057be59728664b1
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
    ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
    ${COMMON_DEPS_CONFIGURE_ARGS}
    --with-gmp-prefix=${DEPS_DIR}
    --disable-shared
    )

ExternalProject_add(cloog
    DEPENDS gmp isl
    URL http://www.bastoul.net/cloog/pages/download/cloog-0.18.4.tar.gz
    URL_MD5 e531f725244856c92c9bba009ff44faf
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
    ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
    ${COMMON_DEPS_CONFIGURE_ARGS}
    --with-gmp-prefix=${DEPS_DIR}
    --with-isl-prefix=${DEPS_DIR}
    --disable-shared
    --disable-nls
    --with-bits=gmp
    --with-host-libstdcxx='-lstdc++'
    )

ExternalProject_add(expat
    URL http://downloads.sourceforge.net/sourceforge/expat/expat-2.2.0.tar.bz2
    URL_MD5 2f47841c829facb346eb6e3fab5212e2
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
    ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
    ${COMMON_DEPS_CONFIGURE_ARGS}
    --disable-shared
    --disable-nls
    )

if ("${CMAKE_CXX_COMPILER_ID}" MATCHES "Clang")
    # Clang doesn't seem to support static-libgcc not mixing static/dynamic libraries.
    # Leave GCC_LINKER_ARGS unset.
    if (${CMAKE_SYSTEM_NAME} STREQUAL "Darwin")
        # clang on OSX needs mode depth to compile gcc
        set(EXTRA_CFLAGS -fbracket-depth=512)
    endif(${CMAKE_SYSTEM_NAME} STREQUAL "Darwin")
elseif ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "GNU")
    set(GCC_LINKER_ARGS "--with-host-libstdcxx=-static-libgcc -Wl,-Bstatic,-lstdc++,-Bdynamic -lm")
else ()
    message(FATAL_ERROR "Unsupported compiler: ${CMAKE_CXX_COMPILER_ID}")
endif()


set(COMMON_GCC_CONFIGURE_ARGS
    --build=${BUILD_NATIVE}
    --host=${HOST_NATIVE}
    --target=${TARGET_ARCH}
    --prefix=${CMAKE_INSTALL_PREFIX}
    --libdir=${CMAKE_INSTALL_PREFIX}/lib
    --libexecdir=${CMAKE_INSTALL_PREFIX}/lib
    --with-sysroot=${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH}
    --with-python-dir=share/gcc-${TARGET_ARCH}
    --with-gmp=${DEPS_DIR}
    --with-mpfr=${DEPS_DIR}
    --with-mpc=${DEPS_DIR}
    --with-isl=${DEPS_DIR}
    --with-cloog=${DEPS_DIR}
    --with-libelf=${DEPS_DIR}
    --enable-languages=c,c++
    --enable-plugins
    --enable-threads=posix
    --disable-decimal-float
    --disable-libffi
    --disable-libgomp
    --disable-libmudflap
    --disable-libquadmath
    --disable-libssp
    --disable-libstdcxx-pch
    --disable-nls
    --disable-shared
    --disable-tls
    --with-gnu-as
    --with-gnu-ld
    --with-newlib
    --with-headers=yes
    ${GCC_LINKER_ARGS}
    --disable-multilib
    --with-arch=armv7-a
    --with-tune=cortex-a9
    --with-fpu=neon
    --with-float=hard
    --with-mode=thumb
    )

ExternalProject_add(gcc-base
    DEPENDS gmp mpfr mpc isl cloog libelf expat
    URL http://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.bz2
    URL_MD5 ${GCC_MD5}
    PATCH_COMMAND patch -d <SOURCE_DIR> -p3 -t -N < ${PROJECT_SOURCE_DIR}/patches/gcc.patch
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env CFLAGS=${EXTRA_CFLAGS} CXXFLAGS=${EXTRA_CFLAGS} ${COMPILER_FLAGS} ${TARGET_TOOLS}
    ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
    ${COMMON_GCC_CONFIGURE_ARGS}
    --disable-threads
    --without-headers
    BUILD_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
    ${PROJECT_SOURCE_DIR}/command_wrapper.sh $(MAKE) all-gcc
    INSTALL_COMMAND $(MAKE) install-gcc
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_INSTALL_PREFIX}/include
    )

ExternalProject_add(vita-headers
    DEPENDS ${VITA_HEADERS_DEPENDS}
    GIT_REPOSITORY https://github.com/vitasdk/vita-headers
    GIT_TAG master
    CONFIGURE_COMMAND ""
    BUILD_COMMAND $(MAKE) -C vitalibs ARCH=${BINUTILS_PREFIX}
    INSTALL_COMMAND ""
    COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/vita-headers-version.txt
    )

# generate the vita library stubs
ExternalProject_Add_Step(vita-headers
    create_directory
    DEPENDEES configure
    DEPENDERS build
    WORKING_DIRECTORY <SOURCE_DIR>
    COMMAND ${CMAKE_COMMAND} -E remove_directory <BINARY_DIR>/vitalibs
    COMMAND ${CMAKE_COMMAND} -E make_directory <BINARY_DIR>/vitalibs
    COMMAND ${VITA_LIBS_GEN_COMMAND} <SOURCE_DIR>/db.json <BINARY_DIR>/vitalibs
    COMMENT "Generating vitalibs sources"
    )

file(GLOB vitalibs_stubs <BINARY_DIR>/vitalibs/*.a)

# copy generated headers and stubs to the install directory
ExternalProject_Add_Step(vita-headers
    copy_files
    DEPENDEES build
    WORKING_DIRECTORY <SOURCE_DIR>
    COMMAND ${CMAKE_COMMAND}
    -DSTUBS_DIR=<BINARY_DIR>/vitalibs
    -DINSTALL_DIR=${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH}/lib
    -P ${CMAKE_SOURCE_DIR}/cmake/copy_vita_stubs.cmake
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH}/include
    COMMAND ${CMAKE_COMMAND} -E copy_directory include ${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH}/include
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_INSTALL_PREFIX}/share
    COMMAND ${CMAKE_COMMAND} -E copy db.json ${CMAKE_INSTALL_PREFIX}/share
    COMMENT "Copying libraries and headers"
    )

ExternalProject_Add(newlib
    DEPENDS binutils gcc-base
    GIT_REPOSITORY https://github.com/vitasdk/newlib
    GIT_TAG vita
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS} ${TARGET_TOOLS}
    "CFLAGS_FOR_TARGET=${CFLAGS_FOR_TARGET}"
    ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
    --build=${BUILD_NATIVE}
    --host=${HOST_NATIVE}
    --target=${TARGET_ARCH}
    --prefix=${CMAKE_INSTALL_PREFIX}
    --enable-newlib-io-long-long
    --enable-newlib-register-fini
    --disable-newlib-supplied-syscalls
    --disable-nls
    BUILD_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
    ${PROJECT_SOURCE_DIR}/command_wrapper.sh $(MAKE)
    INSTALL_COMMAND $(MAKE) install
    COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/newlib-version.txt
    )

ExternalProject_Add(pthread-embedded
    DEPENDS binutils newlib binutils gcc-base
    GIT_REPOSITORY https://github.com/vitasdk/pthread-embedded
    GIT_TAG master
    BUILD_IN_SOURCE 1
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
    ${PROJECT_SOURCE_DIR}/command_wrapper.sh $(MAKE)
    PREFIX=${CMAKE_INSTALL_PREFIX} -C <SOURCE_DIR>/platform/vita ${PTHREAD_TOOLS}
    INSTALL_COMMAND $(MAKE) -C <SOURCE_DIR>/platform/vita PREFIX=${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH} install
    COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/pthread-embedded-version.txt
    )

ExternalProject_add(gcc-final
    DEPENDS gmp mpfr mpc isl cloog libelf expat newlib binutils gcc-base pthread-embedded
    URL http://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.bz2
    URL_MD5 ${GCC_MD5}
    PATCH_COMMAND patch -d <SOURCE_DIR> -p3 -t -N < ${PROJECT_SOURCE_DIR}/patches/gcc.patch
    COMMAND ${CMAKE_COMMAND} -E create_symlink . ${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH}/usr
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env CFLAGS=${EXTRA_CFLAGS} CXXFLAGS=${EXTRA_CFLAGS} ${COMPILER_FLAGS} ${TARGET_TOOLS}
    ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
    ${COMMON_GCC_CONFIGURE_ARGS}
    --enable-plugins
    --enable-threads=posix
    --with-headers=yes
    BUILD_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
    ${PROJECT_SOURCE_DIR}/command_wrapper.sh $(MAKE) INHIBIT_LIBC_CFLAGS="-DUSE_TM_CLONE_REGISTRY=0"
    INSTALL_COMMAND $(MAKE) install
    COMMAND ${CMAKE_COMMAND} -E remove -f ${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH}/usr
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_INSTALL_PREFIX}/include
    )

ExternalProject_Add(samples
    GIT_REPOSITORY https://github.com/vitasdk/samples
    GIT_TAG master
    BUILD_IN_SOURCE 1
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ""
    INSTALL_COMMAND ${CMAKE_COMMAND}
    -DSOURCE=<SOURCE_DIR> -DDEST=${CMAKE_INSTALL_PREFIX}/share/gcc-${TARGET_ARCH}
    -P ${CMAKE_SOURCE_DIR}/cmake/install_files.cmake
    COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/samples-version.txt
    )

# remove .la files
add_custom_target(pretidy
    COMMAND ${CMAKE_COMMAND}
    -DPATTERN=${CMAKE_INSTALL_PREFIX}/*.la
    -P ${CMAKE_SOURCE_DIR}/cmake/remove_files.cmake
    DEPENDS vita-headers gcc-final
    COMMENT "Removing .la files"
    )

# strip toolchain binaries to reduce filesize
add_custom_target(strip_host_binaries
    COMMAND ${CMAKE_COMMAND} -DHOST_SYSTEM_NAME=${CMAKE_HOST_SYSTEM_NAME}
    -DBINDIR=${CMAKE_INSTALL_PREFIX}/bin
    -P ${CMAKE_SOURCE_DIR}/cmake/strip_host_binaries.cmake

    COMMAND ${CMAKE_COMMAND} -DHOST_SYSTEM_NAME=${CMAKE_HOST_SYSTEM_NAME}
    -DBINDIR=${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH}/bin
    -P ${CMAKE_SOURCE_DIR}/cmake/strip_host_binaries.cmake

    COMMAND ${CMAKE_COMMAND} -DHOST_SYSTEM_NAME=${CMAKE_HOST_SYSTEM_NAME}
    -DBINDIR=${CMAKE_INSTALL_PREFIX}/lib/gcc/${TARGET_ARCH}/${GCC_VERSION}
    -P ${CMAKE_SOURCE_DIR}/cmake/strip_host_binaries.cmake

    DEPENDS vita-toolchain binutils gcc-final
    COMMENT "Stripping host binaries"
    )

# remove unnecessary sections from tolchain libraries
add_custom_target(strip_target_objects
    COMMAND ${CMAKE_COMMAND} -DBINDIR=${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH}/lib
    -DOBJCOPY_CMD=${CMAKE_INSTALL_PREFIX}/bin/${TARGET_ARCH}-objcopy
    -P ${CMAKE_SOURCE_DIR}/cmake/strip_target_objects.cmake

    COMMAND ${CMAKE_COMMAND} -DBINDIR=${CMAKE_INSTALL_PREFIX}/lib/gcc/${TARGET_ARCH}/${GCC_VERSION}
    -DOBJCOPY_CMD=${CMAKE_INSTALL_PREFIX}/bin/${TARGET_ARCH}-objcopy
    -P ${CMAKE_SOURCE_DIR}/cmake/strip_target_objects.cmake

    DEPENDS vita-headers gcc-final
    COMMENT "Stripping target objects"
    )

# merge the commit ids of the collected projects into a single file
add_custom_target(version_info
    COMMAND ${CMAKE_COMMAND} -DINPUT_DIR=${CMAKE_BINARY_DIR} -DOUTPUT_DIR=${CMAKE_INSTALL_PREFIX}
    -P ${CMAKE_SOURCE_DIR}/cmake/create_version.cmake
    DEPENDS vita-headers vita-toolchain newlib pthread-embedded samples
    )

# create a sdk tarball
add_custom_target(tarball ALL
    COMMAND ${CMAKE_COMMAND} -E tar "cfvj" "vitasdk-${BUILD_NATIVE}-${BUILD_DATE}.tar.bz2" "${CMAKE_INSTALL_PREFIX}"
    DEPENDS vita-toolchain vita-headers newlib pthread-embedded samples binutils gcc-final
    DEPENDS pretidy strip_host_binaries strip_target_objects version_info
    COMMENT "Creating vitasdk-${host_os}-${BUILD_DATE}.tar.bz2"
    )
