#
# Copyright(c) 2016 codestation
# Distributed under the MIT License (http://opensource.org/licenses/MIT)
#

# Function to build the dependencies required for the vitasdk toolchain/headers
function(toolchain_deps toolchain_deps_dir toolchain_install_dir toolchain_suffix)
    set(extra_macro_args ${ARGN})
    # Every CMake-configured sub-project gets these; see CMakeLists.txt.
    set(toolchain_cmake_args ${compiler_launcher_args})
    set(libelf_patch_series
        "${PROJECT_SOURCE_DIR}/patches/libelf-configure-in.patch|1")
    set(binutils_patch_series
        "${PROJECT_SOURCE_DIR}/patches/binutils/0001-vita.patch|1"
        "${PROJECT_SOURCE_DIR}/patches/binutils/0002-fix-broken-reloc.patch|1"
        "${PROJECT_SOURCE_DIR}/patches/binutils/0003-fix-elf-vaddr.patch|1"
        "${PROJECT_SOURCE_DIR}/patches/binutils/0004-fix-interworking-veneers.patch|1"
        "${PROJECT_SOURCE_DIR}/patches/binutils/0005-genscripts-mkdir.patch|1")
    set(gdb_patch_series
        "${PROJECT_SOURCE_DIR}/patches/gdb.patch|1"
        "${PROJECT_SOURCE_DIR}/patches/gdb-zlib.patch|1"
        "${PROJECT_SOURCE_DIR}/patches/gdb/0001-clang-enum-flags.patch|1")
    list(JOIN libelf_patch_series "^" libelf_patch_series_arg)
    list(JOIN binutils_patch_series "^" binutils_patch_series_arg)
    list(JOIN gdb_patch_series "^" gdb_patch_series_arg)

    # Check if the toolchain file has been passed as optional argument
    list(LENGTH extra_macro_args num_extra_args)
    if(${num_extra_args} GREATER 0)
        list(GET extra_macro_args 0 toolchain_file)
    endif()

    if(toolchain_file)
        # Use the host triplet when crosscompiling
        set(toolchain_host ${host_native})
        list(APPEND toolchain_cmake_args -DCMAKE_TOOLCHAIN_FILE=${toolchain_file})
        # Workaround for libelf configure step (doesn't detect the toolchain)
        set(cc_compiler "${host_native}-gcc")
        set(ranlib "${host_native}-ranlib")
        set(dependency_c_flags "${CMAKE_C_FLAGS}")
        set(dependency_cxx_flags "${CMAKE_CXX_FLAGS}")
        set(dependency_link_flags "${CMAKE_EXE_LINKER_FLAGS}")
    else()
        # Use the same host triplet as the build env
        set(toolchain_host ${build_native})
        # Use the default toolchain
        set(cc_compiler "gcc")
        set(ranlib "ranlib")
        vitasdk_get_host_static_flags("${CMAKE_HOST_SYSTEM_NAME}"
            build_static_c_flags build_static_cxx_flags build_static_link_flags)
        set(dependency_c_flags "${vitasdk_base_c_flags}")
        set(dependency_cxx_flags "${vitasdk_base_cxx_flags}")
        set(dependency_link_flags "${vitasdk_base_link_flags}")
        vitasdk_append_flags(dependency_c_flags ${build_static_c_flags})
        vitasdk_append_flags(dependency_cxx_flags ${build_static_cxx_flags})
        vitasdk_append_flags(dependency_link_flags ${build_static_link_flags})
    endif()

    list(APPEND toolchain_cmake_args
        "-DCMAKE_C_FLAGS=${dependency_c_flags}"
        "-DCMAKE_CXX_FLAGS=${dependency_cxx_flags}"
        "-DCMAKE_EXE_LINKER_FLAGS=${dependency_link_flags}")

    set(suffix "_${toolchain_suffix}")

    if(toolchain_file AND CMAKE_SYSTEM_NAME STREQUAL "Windows")
        set(zlib_static_archive <BINARY_DIR>/libzlibstatic.a)
    else()
        set(zlib_static_archive <BINARY_DIR>/libz.a)
    endif()
    ExternalProject_Add(zlib${suffix}
        URL ${ZLIB_URL}
        URL_HASH ${ZLIB_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=${toolchain_deps_dir}
        ${toolchain_cmake_args}
        -DBUILD_SHARED_LIBS=OFF
        -DZLIB_BUILD_EXAMPLES=OFF
        BUILD_COMMAND ${CMAKE_COMMAND} --build <BINARY_DIR> --target zlibstatic
        INSTALL_COMMAND ${CMAKE_COMMAND} -E make_directory
            ${toolchain_deps_dir}/include ${toolchain_deps_dir}/lib/pkgconfig
        COMMAND ${CMAKE_COMMAND} -E copy
            ${zlib_static_archive} ${toolchain_deps_dir}/lib/libz.a
        COMMAND ${CMAKE_COMMAND} -E copy
            <SOURCE_DIR>/zlib.h <BINARY_DIR>/zconf.h ${toolchain_deps_dir}/include
        COMMAND ${CMAKE_COMMAND} -E copy
            <BINARY_DIR>/zlib.pc ${toolchain_deps_dir}/lib/pkgconfig/zlib.pc
        )

    list(APPEND toolchain_cmake_args -DBUILD_SHARED_LIBS=OFF)

    # vita-toolchain consumes libzip only as a static archive, so every optional
    # crypto, compression, tool, test, fuzzer, example and documentation feature
    # is disabled explicitly instead of relying on the upstream defaults, which
    # enable all of them. libzip uses GNUInstallDirs, so the library directory is
    # pinned to "lib" to keep the archive path predictable on hosts that would
    # otherwise select lib64.
    ExternalProject_Add(libzip${suffix}
        DEPENDS zlib${suffix}
        URL ${LIBZIP_URL}
        URL_HASH ${LIBZIP_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=${toolchain_deps_dir}
        ${toolchain_cmake_args}
        -DCMAKE_INSTALL_LIBDIR=lib
        -DZLIB_INCLUDE_DIR=${toolchain_deps_dir}/include
        -DZLIB_LIBRARY=${toolchain_deps_dir}/lib/libz.a
        -DENABLE_COMMONCRYPTO=OFF
        -DENABLE_GNUTLS=OFF
        -DENABLE_MBEDTLS=OFF
        -DENABLE_OPENSSL=OFF
        -DENABLE_WINDOWS_CRYPTO=OFF
        -DENABLE_BZIP2=OFF
        -DENABLE_LZMA=OFF
        -DENABLE_ZSTD=OFF
        -DBUILD_TOOLS=OFF
        -DBUILD_REGRESS=OFF
        -DBUILD_OSSFUZZ=OFF
        -DBUILD_EXAMPLES=OFF
        -DBUILD_DOC=OFF
        )

    # USE_BUNDLED_ENDIAN_H is a vita-toolchain option rather than a libzip one,
    # so it is appended after libzip is declared and never reaches a project that
    # does not define it.
    if(NOT ${CMAKE_SYSTEM_NAME} STREQUAL "Windows")
        list(APPEND toolchain_cmake_args -DUSE_BUNDLED_ENDIAN_H=ON)
    endif()

    ExternalProject_add(libelf${suffix}
        DEPENDS zlib${suffix}
        URL ${LIBELF_URL}
        URL_HASH ${LIBELF_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        PATCH_COMMAND ${CMAKE_COMMAND}
            -DSOURCE_DIR=<SOURCE_DIR>
            "-DPATCH_SERIES=${libelf_patch_series_arg}"
            -P ${PROJECT_SOURCE_DIR}/cmake/ApplyPatches.cmake
        COMMAND autoreconf -i <SOURCE_DIR>
        COMMAND ${CMAKE_COMMAND} -E copy
            ${PROJECT_SOURCE_DIR}/config.guess
            ${PROJECT_SOURCE_DIR}/config.sub
            <SOURCE_DIR>/
        CONFIGURE_COMMAND CC=${cc_compiler} RANLIB=${ranlib} ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --prefix=${toolchain_deps_dir}
        --libdir=${toolchain_deps_dir}/lib
        --disable-shared
        --disable-nls
        BUILD_COMMAND ${compiler_flags} ${wrapper_command} $(MAKE)
        )

    ExternalProject_add(libyaml${suffix}
        URL ${LIBYAML_URL}
        URL_HASH ${LIBYAML_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        PATCH_COMMAND ${CMAKE_COMMAND} -E copy ${PROJECT_SOURCE_DIR}/config.guess ${PROJECT_SOURCE_DIR}/config.sub <SOURCE_DIR>/config/
        CONFIGURE_COMMAND ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --prefix=${toolchain_deps_dir}
        --libdir=${toolchain_deps_dir}/lib
        --disable-shared
        --enable-static
        "CFLAGS=-DYAML_DECLARE_STATIC"
        BUILD_COMMAND ${compiler_flags} ${wrapper_command} $(MAKE)
        )

    ExternalProject_add(gmp${suffix}
        URL ${GMP_URL}
        URL_HASH ${GMP_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        CONFIGURE_COMMAND CFLAGS=-std=gnu99 CPPFLAGS=-fexceptions ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --prefix=${toolchain_deps_dir}
        --libdir=${toolchain_deps_dir}/lib
        --enable-cxx
        --disable-shared
        --enable-static
        # gmp's x86_64 assembly reaches its lookup tables from the text
        # segment, which Apple's linker refuses inside a position-independent
        # executable; every host that links this statically wants it anyway.
        --with-pic
        BUILD_COMMAND ${compiler_flags} ${wrapper_command} $(MAKE)
        )

    ExternalProject_add(mpfr${suffix}
        DEPENDS gmp${suffix}
        URL ${MPFR_URL}
        URL_HASH ${MPFR_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        CONFIGURE_COMMAND ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --prefix=${toolchain_deps_dir}
        --libdir=${toolchain_deps_dir}/lib
        --with-gmp=${toolchain_deps_dir}
        --disable-shared
        --enable-static
        BUILD_COMMAND ${compiler_flags} ${wrapper_command} $(MAKE)
        )

    ExternalProject_add(mpc${suffix}
        DEPENDS gmp${suffix} mpfr${suffix}
        URL ${MPC_URL}
        URL_HASH ${MPC_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        CONFIGURE_COMMAND ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --prefix=${toolchain_deps_dir}
        --libdir=${toolchain_deps_dir}/lib
        --with-gmp=${toolchain_deps_dir}
        --with-mpfr=${toolchain_deps_dir}
        --disable-shared
        --enable-static
        --disable-nls
        BUILD_COMMAND ${compiler_flags} ${wrapper_command} $(MAKE)
        )

    ExternalProject_add(isl${suffix}
        DEPENDS gmp${suffix}
        GIT_REPOSITORY ${ISL_REPOSITORY}
        GIT_TAG ${ISL_TAG}
        ${GIT_SHALLOW_SUPPORT}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        GIT_SUBMODULES ""
        PATCH_COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR>
            submodule update --init --recursive --depth 1
        COMMAND ${CMAKE_COMMAND} -E chdir <SOURCE_DIR> ./autogen.sh
        CONFIGURE_COMMAND ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --prefix=${toolchain_deps_dir}
        --libdir=${toolchain_deps_dir}/lib
        --with-gmp-prefix=${toolchain_deps_dir}
        --disable-shared
        --enable-static
        BUILD_COMMAND ${compiler_flags} ${wrapper_command} $(MAKE)
        ${UPDATE_DISCONNECTED_SUPPORT}
        )

    if(NOT VITASDK_TARGET_ONLY)
        # Only gdb reads XML target descriptions; a producer has no gdb.
        ExternalProject_add(expat${suffix}
            URL ${EXPAT_URL}
            URL_HASH ${EXPAT_HASH}
            DOWNLOAD_DIR ${DOWNLOAD_DIR}
            DOWNLOAD_EXTRACT_TIMESTAMP TRUE
            CONFIGURE_COMMAND ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
            --build=${build_native}
            --host=${toolchain_host}
            --prefix=${toolchain_deps_dir}
            --libdir=${toolchain_deps_dir}/lib
            --disable-shared
            --enable-static
            BUILD_COMMAND ${compiler_flags} ${wrapper_command} $(MAKE)
            )
    endif()

    ExternalProject_Add(vita-toolchain${suffix}
        DEPENDS libelf${suffix} zlib${suffix} libzip${suffix} libyaml${suffix}
        GIT_REPOSITORY ${TOOLCHAIN_REPOSITORY}
        GIT_TAG ${TOOLCHAIN_TAG}
        # ExternalProject's GIT_SHALLOW only applies to the top-level clone.
        # Initialize this required submodule explicitly at depth 1 as well.
        GIT_SUBMODULES ""
        PATCH_COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR>
            submodule update --init --recursive --depth 1
        # Set prefix to "/" here to be able to install twice
        CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=/ ${toolchain_cmake_args}
        -DTOOLCHAIN_DEPS_DIR=${toolchain_deps_dir}
        -Dlibelf_LIBRARY=${toolchain_deps_dir}/lib/libelf.a
        -Dzlib_LIBRARY=${toolchain_deps_dir}/lib/libz.a
        -Dlibzip_LIBRARY=${toolchain_deps_dir}/lib/libzip.a
        -Dlibyaml_LIBRARY=${toolchain_deps_dir}/lib/libyaml.a
        BUILD_COMMAND $(MAKE)
        INSTALL_COMMAND $(MAKE) install DESTDIR=${toolchain_install_dir}
        # Save the commit id for tracking purposes
        COMMAND ${GIT_EXECUTABLE} -C <SOURCE_DIR> rev-parse HEAD > ${CMAKE_BINARY_DIR}/vita-toolchain-version.txt
        ${UPDATE_DISCONNECTED_SUPPORT}
        )

    ExternalProject_Add(binutils${suffix}
        DEPENDS zlib${suffix}
        URL ${BINUTILS_URL}
        URL_HASH ${BINUTILS_HASH}
        DOWNLOAD_DIR ${DOWNLOAD_DIR}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        PATCH_COMMAND ${CMAKE_COMMAND}
            -DSOURCE_DIR=<SOURCE_DIR>
            "-DPATCH_SERIES=${binutils_patch_series_arg}"
            -P ${PROJECT_SOURCE_DIR}/cmake/ApplyPatches.cmake
        COMMAND ${CMAKE_COMMAND} -E copy
            ${PROJECT_SOURCE_DIR}/config.guess
            ${PROJECT_SOURCE_DIR}/config.sub
            <SOURCE_DIR>/
        CONFIGURE_COMMAND CFLAGS=-std=gnu11 ${libtool_static_env}
        ${compiler_flags}
        ${wrapper_command} <SOURCE_DIR>/configure
        --build=${build_native}
        --host=${toolchain_host}
        --target=${target_arch}
        # Set prefix to "/" here to be able to install twice
        --prefix=/
        --with-sysroot=${toolchain_install_dir}
        --disable-nls
        --disable-werror
        --disable-separate-code
        --enable-interwork
        --enable-plugins
        --without-zstd
        "--with-pkgversion=${pkgversion}"
        BUILD_COMMAND $(MAKE) INFO_DEPS= DVIS= pdfs= htmls=
        INSTALL_COMMAND $(MAKE) install DESTDIR=${toolchain_install_dir} INFO_DEPS= DVIS= pdfs= htmls=
        )

    if(NOT VITASDK_TARGET_ONLY)
        # gdb is a host binary through and through: it never takes part in
        # producing target code, and every host builds its own.
        ExternalProject_Add(gdb${suffix}
            DEPENDS zlib${suffix} gmp${suffix} mpfr${suffix} expat${suffix}
            URL ${GDB_URL}
            URL_HASH ${GDB_HASH}
            DOWNLOAD_DIR ${DOWNLOAD_DIR}
            DOWNLOAD_EXTRACT_TIMESTAMP TRUE
            PATCH_COMMAND ${CMAKE_COMMAND}
                -DSOURCE_DIR=<SOURCE_DIR>
                "-DPATCH_SERIES=${gdb_patch_series_arg}"
                -P ${PROJECT_SOURCE_DIR}/cmake/ApplyPatches.cmake
            COMMAND ${CMAKE_COMMAND} -E copy
                ${PROJECT_SOURCE_DIR}/config.guess
                ${PROJECT_SOURCE_DIR}/config.sub
                <SOURCE_DIR>/
            CONFIGURE_COMMAND CFLAGS=-std=gnu11 ${libtool_static_env}
            ${compiler_flags} ${wrapper_command} <SOURCE_DIR>/configure
            --build=${build_native}
            --host=${toolchain_host}
            --target=${target_arch}
            # Set prefix to "/" here to be able to install twice
            --prefix=/
            --with-sysroot=${toolchain_install_dir}
            --without-system-zlib
            --without-system-readline
            --disable-tui
            --without-zstd
            --without-python
            --without-guile
            --without-lzma
            --without-babeltrace
            --without-xxhash
            # Every other component here disables it. Left on, gdb links the
            # host's libintl -- on Intel macOS that is Homebrew's, which the
            # dependency audit refuses and a user's machine would not have.
            --disable-nls
            --without-debuginfod
            --with-gmp=${toolchain_deps_dir}
            --with-mpfr=${toolchain_deps_dir}
            --with-expat
            --with-libexpat-prefix=${toolchain_deps_dir}
            --with-libexpat-type=static
            # GDB provides stub-termcap when tgetent is unavailable. Propagate both
            # cache answers to the GDB and bundled Readline sub-configures so they
            # cannot auto-link the runner's libtinfo/ncurses.
            "host_configargs=ac_cv_search_tgetent=no bash_cv_termcap_lib=libc"
            BUILD_COMMAND $(MAKE) INFO_DEPS= DVIS= pdfs= htmls=
            INSTALL_COMMAND $(MAKE) install DESTDIR=${toolchain_install_dir} INFO_DEPS= DVIS= pdfs= htmls=
            )
    endif()

    # Install binutils, gdb and vita-toolchain on CMAKE_INSTALL_PREFIX when not crosscompiling
    if(NOT toolchain_file AND "${host_native}" STREQUAL "${build_native}")
        ExternalProject_Add_Step(binutils${suffix}
            install_sdk
            DEPENDEES install
            COMMAND $(MAKE) -C <BINARY_DIR> install DESTDIR=${CMAKE_INSTALL_PREFIX}
            COMMENT "Installing binutils to ${CMAKE_INSTALL_PREFIX}"
            )

        if(NOT VITASDK_TARGET_ONLY)

            ExternalProject_Add_Step(gdb${suffix}
                install_sdk
                DEPENDEES install
                COMMAND $(MAKE) -C <BINARY_DIR> install DESTDIR=${CMAKE_INSTALL_PREFIX}
                COMMENT "Installing gdb to ${CMAKE_INSTALL_PREFIX}"
                )
        endif()

        ExternalProject_Add_Step(vita-toolchain${suffix}
            install_sdk
            DEPENDEES install
            COMMAND $(MAKE) -C <BINARY_DIR> install DESTDIR=${CMAKE_INSTALL_PREFIX}
            COMMENT "Installing vita-toolchain to ${CMAKE_INSTALL_PREFIX}"
            )
    endif()
endfunction()
