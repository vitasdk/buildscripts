cmake_minimum_required(VERSION 3.0.2)

project(vitasdk)

find_package(Git REQUIRED)

list(APPEND CMAKE_MODULE_PATH "${PROJECT_SOURCE_DIR}/cmake")

# Use the following gcc version
set(GCC_VERSION 5.4.0)
set(GCC_MD5 4c626ac2a83ef30dfb9260e6f59c2b30)

# Installation directory
set(CMAKE_INSTALL_PREFIX ${CMAKE_BINARY_DIR}/vitasdk)
# Toolchain arch target
set(TARGET_ARCH arm-vita-eabi)
# build date
string(TIMESTAMP BUILD_DATE "%Y-%m-%d_%H-%M-%S")

include(Utils)
include(GetTriplet)
include(ExternalProject)

# Identify host and build systems
get_host_triplet(HOST_NATIVE)
get_build_triplet(BUILD_NATIVE)

message(STATUS "Host:   ${HOST_NATIVE}")
message(STATUS "Build:  ${BUILD_NATIVE}")
message(STATUS "Target: ${TARGET_ARCH}")

# load the compiler flags to pass them to the other projects
load_flags(COMPILER_FLAGS)

# Macro to build the dependencies required for the vitasdk toolchain/headers
function(toolchain_deps TOOLCHAIN_DEPS_DIR TOOLCHAIN_INSTALL_DIR TOOLCHAIN_SUFFIX)
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
        set(TOOLCHAIN_HOST --host=${BUILD_NATIVE})
        set(CC_COMPILER "gcc")
    endif ()

    set(COMMON_DEPS_CONFIGURE_ARGS
        --build=${BUILD_NATIVE}
        ${TOOLCHAIN_HOST}
        --prefix=${TOOLCHAIN_INSTALL_DIR}
        --libdir=${TOOLCHAIN_INSTALL_DIR}/lib
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
        --prefix=${TOOLCHAIN_DEPS_DIR}
        --libdir=${TOOLCHAIN_DEPS_DIR}/lib
        --disable-shared
        --enable-static
        )

    ExternalProject_add(gmp${TOOLCHAIN_SUFFIX}
        URL https://gmplib.org/download/gmp/gmp-6.1.1.tar.bz2
        URL_MD5 4c175f86e11eb32d8bf9872ca3a8e11d
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env CPPFLAGS=-fexceptions ${COMPILER_FLAGS}
        ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
        --build=${BUILD_NATIVE}
        ${TOOLCHAIN_HOST}
        --prefix=${TOOLCHAIN_DEPS_DIR}
        --libdir=${TOOLCHAIN_DEPS_DIR}/lib
        --enable-cxx
        --disable-shared
        BUILD_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
        ${PROJECT_SOURCE_DIR}/command_wrapper.sh $(MAKE)
        )

    ExternalProject_add(mpfr${TOOLCHAIN_SUFFIX}
        DEPENDS gmp${TOOLCHAIN_SUFFIX}
        URL http://ftp.gnu.org/gnu/mpfr/mpfr-3.1.5.tar.bz2
        URL_MD5 b1d23a55588e3b2a13e3be66bc69fd8d
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
        ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
        --build=${BUILD_NATIVE}
        ${TOOLCHAIN_HOST}
        --prefix=${TOOLCHAIN_DEPS_DIR}
        --libdir=${TOOLCHAIN_DEPS_DIR}/lib
        --with-gmp=${TOOLCHAIN_DEPS_DIR}
        --disable-shared
        )

    ExternalProject_add(mpc${TOOLCHAIN_SUFFIX}
        DEPENDS gmp${TOOLCHAIN_SUFFIX} mpfr${TOOLCHAIN_SUFFIX}
        URL http://www.multiprecision.org/mpc/download/mpc-1.0.3.tar.gz
        URL_MD5 d6a1d5f8ddea3abd2cc3e98f58352d26
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
        ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
        --build=${BUILD_NATIVE}
        ${TOOLCHAIN_HOST}
        --prefix=${TOOLCHAIN_DEPS_DIR}
        --libdir=${TOOLCHAIN_DEPS_DIR}/lib
        --with-gmp=${TOOLCHAIN_DEPS_DIR}
        --with-mpfr=${TOOLCHAIN_DEPS_DIR}
        --disable-shared
        --disable-nls
        )

    ExternalProject_add(isl${TOOLCHAIN_SUFFIX}
        DEPENDS gmp${TOOLCHAIN_SUFFIX}
        URL http://isl.gforge.inria.fr/isl-0.17.1.tar.bz2
        URL_MD5 5184f543a013165e8057be59728664b1
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
        ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
        --build=${BUILD_NATIVE}
        ${TOOLCHAIN_HOST}
        --prefix=${TOOLCHAIN_DEPS_DIR}
        --libdir=${TOOLCHAIN_DEPS_DIR}/lib
        --with-gmp-prefix=${TOOLCHAIN_DEPS_DIR}
        --disable-shared
        )

    ExternalProject_add(cloog${TOOLCHAIN_SUFFIX}
        DEPENDS gmp${TOOLCHAIN_SUFFIX} isl${TOOLCHAIN_SUFFIX}
        URL http://www.bastoul.net/cloog/pages/download/cloog-0.18.4.tar.gz
        URL_MD5 e531f725244856c92c9bba009ff44faf
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
        ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
        --build=${BUILD_NATIVE}
        ${TOOLCHAIN_HOST}
        --prefix=${TOOLCHAIN_DEPS_DIR}
        --libdir=${TOOLCHAIN_DEPS_DIR}/lib
        --with-gmp-prefix=${TOOLCHAIN_DEPS_DIR}
        --with-isl-prefix=${TOOLCHAIN_DEPS_DIR}
        --disable-shared
        --disable-nls
        --with-bits=gmp
        --with-host-libstdcxx='-lstdc++'
        )

    ExternalProject_add(expat${TOOLCHAIN_SUFFIX}
        URL http://downloads.sourceforge.net/sourceforge/expat/expat-2.2.0.tar.bz2
        URL_MD5 2f47841c829facb346eb6e3fab5212e2
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
        ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
        --build=${BUILD_NATIVE}
        ${TOOLCHAIN_HOST}
        --prefix=${TOOLCHAIN_DEPS_DIR}
        --libdir=${TOOLCHAIN_DEPS_DIR}/lib
        --disable-shared
        )

    ExternalProject_Add(vita-toolchain${TOOLCHAIN_SUFFIX}
        DEPENDS jansson${TOOLCHAIN_SUFFIX} libelf${TOOLCHAIN_SUFFIX} zlib${TOOLCHAIN_SUFFIX} libzip${TOOLCHAIN_SUFFIX}
        GIT_REPOSITORY https://github.com/vitasdk/vita-toolchain
        GIT_TAG master
        CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=/
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
        INSTALL_COMMAND $(MAKE) install DESTDIR=${TOOLCHAIN_INSTALL_DIR}
        COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/vita-toolchain-version.txt
        )

    ExternalProject_Add(binutils${TOOLCHAIN_SUFFIX}
        URL https://ftp.gnu.org/gnu/binutils/binutils-2.27.tar.bz2
        URL_MD5 2869c9bf3e60ee97c74ac2a6bf4e9d68
        PATCH_COMMAND patch -d <SOURCE_DIR> -p3 -t -N < ${PROJECT_SOURCE_DIR}/patches/binutils.patch
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
        ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
        --build=${BUILD_NATIVE}
        ${TOOLCHAIN_HOST}
        --target=${TARGET_ARCH}
        --prefix=/
        --with-sysroot=${TOOLCHAIN_INSTALL_DIR}
        --disable-multilib
        --disable-nls
        --disable-shared
        --disable-werror
        --enable-interwork
        --enable-plugins
        BUILD_COMMAND $(MAKE) -j${MAKEJOBS}
        INSTALL_COMMAND $(MAKE) install DESTDIR=${TOOLCHAIN_INSTALL_DIR}
        )

    if (NOT TOOLCHAIN_FILE AND "${HOST_NATIVE}" STREQUAL "${BUILD_NATIVE}")
        ExternalProject_Add_Step(binutils${TOOLCHAIN_SUFFIX}
            install_sdk
            DEPENDEES install
            COMMAND $(MAKE) -C <BINARY_DIR> install DESTDIR=${CMAKE_INSTALL_PREFIX}
            COMMENT "Installing binutils to ${CMAKE_INSTALL_PREFIX}"
            )

        ExternalProject_Add_Step(vita-toolchain${TOOLCHAIN_SUFFIX}
            install_sdk
            DEPENDEES install
            COMMAND $(MAKE) -C <BINARY_DIR> install DESTDIR=${CMAKE_INSTALL_PREFIX}
            COMMENT "Installing vita-toolchain to ${CMAKE_INSTALL_PREFIX}"
            )
    endif ()
endfunction()

set(HOST_SUFFIX host)
set(BUILD_SUFFIX build)

# Only when using cross compilation
if (CMAKE_TOOLCHAIN_FILE)
    set(TARGET_SUFFIX ${HOST_SUFFIX})
    # path of the host dependencies for gcc-final
    set(TOOLCHAIN_TARGET_DEPENDS_DIR "${CMAKE_BINARY_DIR}/deps_${TARGET_SUFFIX}")
    # get the absolute path of the toolchain file, relative paths doesn't with external projects
    get_filename_component(TOOLCHAIN_FILEPATH "${CMAKE_TOOLCHAIN_FILE}" ABSOLUTE)
    # build the native vita-toolchain, binutils and gcc-host depdndencies
    toolchain_deps("${TOOLCHAIN_TARGET_DEPENDS_DIR}" "${CMAKE_INSTALL_PREFIX}" "_${HOST_SUFFIX}" "${TOOLCHAIN_FILEPATH}")
else()
    set(TARGET_SUFFIX ${BUILD_SUFFIX})
    # path of the host dependencies for gcc-final
    set(TOOLCHAIN_TARGET_DEPENDS_DIR "${CMAKE_BINARY_DIR}/deps_${TARGET_SUFFIX}")
endif ()

# native toolchain install dir (used to build the real toolchain)
set(TOOLCHAIN_BUILD_INSTALL_DIR ${CMAKE_BINARY_DIR}/toolchain_${BUILD_SUFFIX})
# toolchain dependencies dir
SET(TOOLCHAIN_BUILD_DEPENDS_DIR ${CMAKE_BINARY_DIR}/deps_${BUILD_SUFFIX})
# build the native vita-toolchain, gcc dependencies and native binutils
toolchain_deps("${TOOLCHAIN_BUILD_DEPENDS_DIR}" "${TOOLCHAIN_BUILD_INSTALL_DIR}" "_${BUILD_SUFFIX}")

set(VITA_LIBS_GEN_COMMAND "${TOOLCHAIN_BUILD_INSTALL_DIR}/bin/vita-libs-gen")
set(BINUTILS_PREFIX "${TOOLCHAIN_BUILD_INSTALL_DIR}/bin/${TARGET_ARCH}")

# tools for cross compilation
list(APPEND TOOLCHAIN_TOOLS
    AR_FOR_TARGET=${BINUTILS_PREFIX}-ar
    LD_FOR_TARGET=${BINUTILS_PREFIX}-ld
    OBJDUMP_FOR_TARGET=${BINUTILS_PREFIX}-objdump
    NM_FOR_TARGET=${BINUTILS_PREFIX}-nm
    RANLIB_FOR_TARGET=${BINUTILS_PREFIX}-ranlib
    READELF_FOR_TARGET=${BINUTILS_PREFIX}-readelf
    STRIP_FOR_TARGET=${BINUTILS_PREFIX}-strip
    AS_FOR_TARGET=${BINUTILS_PREFIX}-as
    )

# tools for cross compilation
list(APPEND COMPILER_TARGET_TOOLS
    CC_FOR_TARGET=${BINUTILS_PREFIX}-gcc
    GCC_FOR_TARGET=${BINUTILS_PREFIX}-gcc
    GXX_FOR_TARGET=${BINUTILS_PREFIX}-g++
    )

# tools for pthread-embedded
list(APPEND PTHREAD_TOOLS
    CC=${BINUTILS_PREFIX}-gcc
    CXX=${BINUTILS_PREFIX}-g++
    AR=${BINUTILS_PREFIX}-ar
    )

# flags for cross compilation
set(CFLAGS_FOR_TARGET "-g -O2 -ffunction-sections -fdata-sections")

if ("${CMAKE_CXX_COMPILER_ID}" MATCHES "Clang")
    # Clang doesn't seem to support static-libgcc not mixing static/dynamic libraries.
    # Leave GCC_LINKER_ARGS unset.
    if (${CMAKE_SYSTEM_NAME} STREQUAL "Darwin")
        # clang on OSX needs mode depth to compile gcc
        set(EXTRA_CFLAGS -fbracket-depth=512)
    endif (${CMAKE_SYSTEM_NAME} STREQUAL "Darwin")
elseif ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "GNU")
    set(GCC_LINKER_ARGS "--with-host-libstdcxx=-static-libgcc -Wl,-Bstatic,-lstdc++,-Bdynamic -lm")
else ()
    message(FATAL_ERROR "Unsupported compiler: ${CMAKE_CXX_COMPILER_ID}")
endif ()

# common gcc configure options
set(COMMON_GCC_CONFIGURE_ARGS
    --with-python-dir=share/gcc-${TARGET_ARCH}
    --enable-languages=c,c++
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
    ${GCC_LINKER_ARGS}
    --disable-multilib
    --with-arch=armv7-a
    --with-tune=cortex-a9
    --with-fpu=neon
    --with-float=hard
    --with-mode=thumb
    )

ExternalProject_add(gcc-base
    DEPENDS gmp_${BUILD_SUFFIX} mpfr_${BUILD_SUFFIX} mpc_${BUILD_SUFFIX} isl_${BUILD_SUFFIX} cloog_${BUILD_SUFFIX} libelf_${BUILD_SUFFIX} expat_${BUILD_SUFFIX}
    URL http://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.bz2
    URL_MD5 ${GCC_MD5}
    PATCH_COMMAND patch -d <SOURCE_DIR> -p3 -t -N < ${PROJECT_SOURCE_DIR}/patches/gcc.patch
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env CFLAGS=${EXTRA_CFLAGS} CXXFLAGS=${EXTRA_CFLAGS} ${COMPILER_FLAGS}
    ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
    --build=${BUILD_NATIVE}
    --target=${TARGET_ARCH}
    --prefix=${TOOLCHAIN_BUILD_INSTALL_DIR}
    --libdir=${TOOLCHAIN_BUILD_INSTALL_DIR}/lib
    --libexecdir=${TOOLCHAIN_BUILD_INSTALL_DIR}/lib
    --with-sysroot=${TOOLCHAIN_BUILD_INSTALL_DIR}/${TARGET_ARCH}
    --with-gmp=${TOOLCHAIN_BUILD_DEPENDS_DIR}
    --with-mpfr=${TOOLCHAIN_BUILD_DEPENDS_DIR}
    --with-mpc=${TOOLCHAIN_BUILD_DEPENDS_DIR}
    --with-isl=${TOOLCHAIN_BUILD_DEPENDS_DIR}
    --with-cloog=${TOOLCHAIN_BUILD_DEPENDS_DIR}
    --with-libelf=${TOOLCHAIN_BUILD_DEPENDS_DIR}
    ${COMMON_GCC_CONFIGURE_ARGS}
    --disable-threads
    --without-headers
    BUILD_COMMAND $(MAKE) all-gcc
    INSTALL_COMMAND $(MAKE) install-gcc
    )

ExternalProject_add(vita-headers
    DEPENDS binutils_${BUILD_SUFFIX} vita-toolchain_${BUILD_SUFFIX}
    GIT_REPOSITORY https://github.com/vitasdk/vita-headers
    GIT_TAG master
    # TODO: vita-libs-gen should generate a proper makefile so this can be simplified
    CONFIGURE_COMMAND ${VITA_LIBS_GEN_COMMAND} <SOURCE_DIR>/db.json <BINARY_DIR>
    BUILD_COMMAND $(MAKE) ARCH=${BINUTILS_PREFIX}
    INSTALL_COMMAND ${CMAKE_COMMAND} -DGLOB_PATTERN=<BINARY_DIR>/*a
    -DINSTALL_DIR=${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH}/lib
    -P ${CMAKE_SOURCE_DIR}/cmake/install_files.cmake
    COMMAND ${CMAKE_COMMAND} -E create_symlink . ${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH}/usr
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH}/include
    COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/include ${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH}/include
    # install a copy of the headers in the toolchain directory
    #COMMAND ${CMAKE_COMMAND} -E make_directory ${TOOLCHAIN_BUILD_INSTALL_DIR}/${TARGET_ARCH}/include
    #COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/include ${TOOLCHAIN_BUILD_INSTALL_DIR}/${TARGET_ARCH}/include
    # copy the json database
    COMMAND ${CMAKE_COMMAND} -DGLOB_PATTERN=<SOURCE_DIR>/db.json -DINSTALL_DIR=${CMAKE_INSTALL_PREFIX}/share
    -P ${CMAKE_SOURCE_DIR}/cmake/install_files.cmake
    COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/vita-headers-version.txt
    )

ExternalProject_Add(newlib
    DEPENDS binutils_${TARGET_SUFFIX} gcc-base vita-headers
    GIT_REPOSITORY https://github.com/vitasdk/newlib
    GIT_TAG vita
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS} ${TOOLCHAIN_TOOLS} ${COMPILER_TARGET_TOOLS}
    "CFLAGS_FOR_TARGET=${CFLAGS_FOR_TARGET}"
    ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
    --build=${BUILD_NATIVE}
    --host=${HOST_NATIVE}
    --target=${TARGET_ARCH}
    --prefix=${CMAKE_INSTALL_PREFIX}
    --with-build-sysroot=${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH}
    --enable-newlib-io-long-long
    --enable-newlib-register-fini
    --disable-newlib-supplied-syscalls
    --disable-nls
    BUILD_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS} ${TOOLCHAIN_TOOLS}
    ${PROJECT_SOURCE_DIR}/command_wrapper.sh $(MAKE)
    INSTALL_COMMAND $(MAKE) install
    # install a copy of newlib in the toolchain directory
    #COMMAND $(MAKE) install DESTDIR=${TOOLCHAIN_BUILD_INSTALL_DIR}
    COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/newlib-version.txt
    )

ExternalProject_Add(pthread-embedded
    DEPENDS binutils_${TARGET_SUFFIX} gcc-base newlib vita-headers
    GIT_REPOSITORY https://github.com/vitasdk/pthread-embedded
    GIT_TAG master
    BUILD_IN_SOURCE 1
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ${CMAKE_COMMAND} -E env ${COMPILER_FLAGS}
    ${PROJECT_SOURCE_DIR}/command_wrapper.sh $(MAKE)
    -C <SOURCE_DIR>/platform/vita ${PTHREAD_TOOLS} PREFIX=${CMAKE_INSTALL_PREFIX}
    INSTALL_COMMAND $(MAKE) -C <SOURCE_DIR>/platform/vita PREFIX=${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH} install
    COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/pthread-embedded-version.txt
    )

ExternalProject_add(gcc-final
    DEPENDS gmp_${TARGET_SUFFIX} mpfr_${TARGET_SUFFIX} mpc_${TARGET_SUFFIX} isl_${TARGET_SUFFIX}
    DEPENDS cloog_${TARGET_SUFFIX} libelf_${TARGET_SUFFIX} expat_${TARGET_SUFFIX}
    DEPENDS binutils_${TARGET_SUFFIX} newlib gcc-base pthread-embedded
    URL http://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.bz2
    URL_MD5 ${GCC_MD5}
    PATCH_COMMAND patch -d <SOURCE_DIR> -p3 -t -N < ${PROJECT_SOURCE_DIR}/patches/gcc.patch
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env CFLAGS=${EXTRA_CFLAGS}
    CXXFLAGS=${EXTRA_CFLAGS} ${COMPILER_FLAGS} ${TOOLCHAIN_TOOLS} ${COMPILER_TARGET_TOOLS}
    ${PROJECT_SOURCE_DIR}/command_wrapper.sh <SOURCE_DIR>/configure
    --build=${BUILD_NATIVE}
    --host=${HOST_NATIVE}
    --target=${TARGET_ARCH}
    --prefix=${CMAKE_INSTALL_PREFIX}
    --libdir=${CMAKE_INSTALL_PREFIX}/lib
    --libexecdir=${CMAKE_INSTALL_PREFIX}/lib
    --with-sysroot=${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH}
    --with-gmp=${TOOLCHAIN_TARGET_DEPENDS_DIR}
    --with-mpfr=${TOOLCHAIN_TARGET_DEPENDS_DIR}
    --with-mpc=${TOOLCHAIN_TARGET_DEPENDS_DIR}
    --with-isl=${TOOLCHAIN_TARGET_DEPENDS_DIR}
    --with-cloog=${TOOLCHAIN_TARGET_DEPENDS_DIR}
    --with-libelf=${TOOLCHAIN_TARGET_DEPENDS_DIR}
    ${COMMON_GCC_CONFIGURE_ARGS}
    --enable-plugins
    --enable-threads=posix
    --with-headers=yes
    BUILD_COMMAND ${CMAKE_COMMAND} -E env ${TOOLCHAIN_TOOLS} ${COMPILER_TARGET_TOOLS}
    $(MAKE) INHIBIT_LIBC_CFLAGS="-DUSE_TM_CLONE_REGISTRY=0"
    INSTALL_COMMAND $(MAKE) install
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_INSTALL_PREFIX}/include
    )

ExternalProject_Add(samples
    GIT_REPOSITORY https://github.com/vitasdk/samples
    GIT_TAG master
    BUILD_IN_SOURCE 1
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ""
    INSTALL_COMMAND ${CMAKE_COMMAND}
    -DGLOB_PATTERN=<SOURCE_DIR> -DINSTALL_DIR=${CMAKE_INSTALL_PREFIX}/share/gcc-${TARGET_ARCH}
    -P ${CMAKE_SOURCE_DIR}/cmake/install_files.cmake
    COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/samples-version.txt
    )

# remove .la files
add_custom_target(pretidy
    COMMAND ${CMAKE_COMMAND}
    -DGLOB_PATTERN=${CMAKE_INSTALL_PREFIX}/*.la
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

    DEPENDS vita-toolchain_${TARGET_SUFFIX} binutils_${TARGET_SUFFIX} gcc-final
    COMMENT "Stripping host binaries"
    )

# remove unnecessary sections from tolchain libraries
add_custom_target(strip_target_objects
    COMMAND ${CMAKE_COMMAND} -DOBJCOPY_COMMAND=${BINUTILS_PREFIX}-objcopy
    -DPATTERN_GLOB=${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH}/lib/*.[ao]
    -P ${CMAKE_SOURCE_DIR}/cmake/strip_target_objects.cmake

    COMMAND ${CMAKE_COMMAND} -DOBJCOPY_COMMAND=${BINUTILS_PREFIX}-objcopy
    -DPATTERN_GLOB=${CMAKE_INSTALL_PREFIX}/lib/gcc/${TARGET_ARCH}/${GCC_VERSION}/*.[ao]
    -P ${CMAKE_SOURCE_DIR}/cmake/strip_target_objects.cmake

    DEPENDS vita-headers gcc-final
    COMMENT "Stripping target objects"
    )

# merge the commit ids of the collected projects into a single file
add_custom_target(version_info
    COMMAND ${CMAKE_COMMAND} -DINPUT_DIR=${CMAKE_BINARY_DIR} -DOUTPUT_DIR=${CMAKE_INSTALL_PREFIX}
    -P ${CMAKE_SOURCE_DIR}/cmake/create_version.cmake
    DEPENDS vita-headers vita-toolchain_${TARGET_SUFFIX} newlib pthread-embedded samples
    )

# remove unnecessary docs
add_custom_target(cleanup
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_INSTALL_PREFIX}/share/man
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_INSTALL_PREFIX}/share/info
    DEPENDS vita-toolchain_${TARGET_SUFFIX} vita-headers newlib pthread-embedded samples binutils_${TARGET_SUFFIX} gcc-final
    COMMENT "Removing gcc/binutils docs"
    )

# create a sdk tarball
add_custom_target(tarball ALL
    COMMAND ${CMAKE_COMMAND} -E tar "cfvj" "vitasdk-${BUILD_NATIVE}-${BUILD_DATE}.tar.bz2" "${CMAKE_INSTALL_PREFIX}"
    DEPENDS vita-toolchain_${TARGET_SUFFIX} vita-headers newlib pthread-embedded samples binutils_${TARGET_SUFFIX} gcc-final
    DEPENDS pretidy cleanup strip_host_binaries strip_target_objects version_info
    COMMENT "Creating vitasdk-${host_os}-${BUILD_DATE}.tar.bz2"
    )
