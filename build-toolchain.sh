#! /usr/bin/env bash
# Copyright (c) 2011-2015, ARM Limited
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
#     * Redistributions of source code must retain the above copyright notice,
#       this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of ARM nor the names of its contributors may be used
#       to endorse or promote products derived from this software without
#       specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

set -e
set -x
set -u
set -o pipefail

umask 022

exec < /dev/null

script_path=`cd $(dirname $0) && pwd -P`
. $script_path/build-common.sh

# This file contains the sequence of commands used to build the ARM EABI toolchain.
usage ()
{
cat<<EOF
Usage: $0 [--build_type=...] [--build_tools=...] [--skip_steps=...]

This script will build gcc arm embedded toolchain.

OPTIONS:
  --build_type=TYPE     specify build type to either ppa or native.
                        If followed by keyword debug, the produced binaries
                        will be debuggable.  The default case will be
                        non-debug native build.

                        Example usages are as:
                        --build_type=native
                        --build_type=ppa
                        --build_type=native,debug
                        --build_type=ppa,debug

  --build_tools=TOOLS   specify where to find the native build tools that
                        will be used for building gcc arm embedded toolchain
                        and related dependent libraries.  If not specified,
                        the ones in your system will be used.

                        The prebuilt ones provided by arm embedded toolchain
                        team are supposed to run on 32bit build platform, thus
                        not suitable for 64bit platform.

  --skip_steps=STEPS    specify which build steps you want to skip.  Concatenate
                        them with comma for skipping more than one steps.  Available
                        steps are: gdb-with-python, mingw32, mingw32-gdb-with-python
                        and manual.
EOF
}

if [ $# -gt 3 ] ; then
    usage
fi

skip_mingw32=no
DEBUG_BUILD_OPTIONS=
is_ppa_release=no
is_native_build=yes
skip_manual=no
skip_steps=
skip_gdb_with_python=no
skip_mingw32_gdb_with_python=no
build_type=
build_tools=

MULTILIB_LIST="--with-multilib-list=armv6-m,armv7-m,armv7e-m,cortex-m7,armv7-r"

for ac_arg; do
    case $ac_arg in
      --skip_steps=*)
	      skip_steps=`echo $ac_arg | sed -e "s/--skip_steps=//g" -e "s/,/ /g"`
	      ;;
      --build_type=*)
	      build_type=`echo $ac_arg | sed -e "s/--build_type=//g" -e "s/,/ /g"`
	      ;;
      --build_tools=*)
	      build_tools=`echo $ac_arg | sed -e "s/--build_tools=//g"`
	      build_tools_abs_path=`cd $build_tools && pwd -P`
	      if [ -d $build_tools_abs_path ]; then
	        if [ -d $build_tools_abs_path/gcc ]; then
	          export PATH=$build_tools_abs_path/gcc/bin:$PATH
	        fi
		if [ -d $build_tools_abs_path/mingw-w64-gcc ]; then
		  export PATH=$build_tools_abs_path/mingw-w64-gcc/bin:$PATH
		fi
		if [ -d $build_tools_abs_path/installjammer ]; then
		  export PATH=$build_tools_abs_path/installjammer:$PATH
		fi
		if [ -d $build_tools_abs_path/nsis ]; then
		  export PATH=$build_tools_abs_path/nsis:$PATH
		fi
		if [ -d $build_tools_abs_path/python ]; then
		  export PATH=$build_tools_abs_path/python/bin:$PATH
		  export LD_LIBRARY_PATH="$build_tools_abs_path/python/lib"
		  export PYTHONHOME="$build_tools_abs_path/python"
		fi
	      else
	        echo "The specified folder of build tools don't exist: $build_tools" 1>&2
		exit 1
	      fi
	      ;;
      *)
        usage
        exit 1
        ;;
    esac
done

if [ "x$build_type" != "x" ]; then
  for bt in $build_type; do
    case $bt in
      ppa)
        is_ppa_release=yes
        is_native_build=no
        skip_gdb_with_python=yes
        ;;
      native)
        is_native_build=yes
        is_ppa_release=no
        ;;
      debug)
        DEBUG_BUILD_OPTIONS=" -O0 -g "
        ;;
      *)
        echo "Unknown build type: $bt" 1>&2
        usage
        exit 1
        ;;
    esac
  done
else
  is_ppa_release=no
  is_native_build=yes
fi

if [ "x$skip_steps" != "x" ]; then
	for ss in $skip_steps; do
		case $ss in
		    manual)
                      skip_manual=yes
                      ;;
		    gdb-with-python)
                      skip_gdb_with_python=yes
                      ;;
	            mingw32)
                      skip_mingw32=yes
                      skip_mingw32_gdb_with_python=yes
                      ;;
                    mingw32-gdb-with-python)
                      skip_mingw32_gdb_with_python=yes
                      ;;
                    *)
                      echo "Unknown build steps: $ss" 1>&2
                      usage
                      exit 1
                      ;;
		esac
	done
fi

if [ "x$BUILD" == "xx86_64-apple-darwin10" ] || [ "x$is_ppa_release" == "xyes" ]; then
    skip_mingw32=yes
    skip_mingw32_gdb_with_python=yes
fi

#Building mingw gdb with python support requires python windows package and
#a special config file. If any of them is missing, we skip the build of
#mingw gdb with python support.
if [ "x$build_tools" == "x" ] || [ ! -d $build_tools_abs_path/python-win ] \
     || [ ! -f $build_tools_abs_path/python-config.sh ]; then
  skip_mingw32_gdb_with_python=yes
fi

if [ "x$is_ppa_release" != "xyes" ]; then
  ENV_CFLAGS=" -I$BUILDDIR_NATIVE/host-libs/zlib/include -O2 "
  ENV_CPPFLAGS=" -I$BUILDDIR_NATIVE/host-libs/zlib/include "
  ENV_LDFLAGS=" -L$BUILDDIR_NATIVE/host-libs/zlib/lib
                -L$BUILDDIR_NATIVE/host-libs/usr/lib "

  if [ "x$build_tools" != "x" ] && [ -d $build_tools_abs_path/python ]; then
    ENV_LDFLAGS+=" -L$build_tools_abs_path/python/lib "
  fi

  GCC_CONFIG_OPTS=" --build=$BUILD --host=$HOST_NATIVE
                    --with-gmp=$BUILDDIR_NATIVE/host-libs/usr
                    --with-mpfr=$BUILDDIR_NATIVE/host-libs/usr
                    --with-mpc=$BUILDDIR_NATIVE/host-libs/usr
                    --with-isl=$BUILDDIR_NATIVE/host-libs/usr
                    --with-cloog=$BUILDDIR_NATIVE/host-libs/usr
                    --with-libelf=$BUILDDIR_NATIVE/host-libs/usr "

  BINUTILS_CONFIG_OPTS=" --build=$BUILD --host=$HOST_NATIVE "

  NEWLIB_CONFIG_OPTS=" --build=$BUILD --host=$HOST_NATIVE "

  GDB_CONFIG_OPTS=" --build=$BUILD --host=$HOST_NATIVE
                    --with-libexpat-prefix=$BUILDDIR_NATIVE/host-libs/usr "
fi

mkdir -p $BUILDDIR_NATIVE
rm -rf $INSTALLDIR_NATIVE && mkdir -p $INSTALLDIR_NATIVE
if [ "x$skip_mingw32" != "xyes" ] ; then
mkdir -p $BUILDDIR_MINGW
rm -rf $INSTALLDIR_MINGW && mkdir -p $INSTALLDIR_MINGW
fi
rm -rf $PACKAGEDIR && mkdir -p $PACKAGEDIR

cd $SRCDIR

echo Task [III-0] /$HOST_NATIVE/binutils/
rm -rf $BUILDDIR_NATIVE/binutils && mkdir -p $BUILDDIR_NATIVE/binutils
pushd $BUILDDIR_NATIVE/binutils
saveenv
saveenvvar CFLAGS "$ENV_CFLAGS"
saveenvvar CPPFLAGS "$ENV_CPPFLAGS"
saveenvvar LDFLAGS "$ENV_LDFLAGS"
$SRCDIR/$BINUTILS/configure  \
    ${BINUTILS_CONFIG_OPTS} \
    --target=$TARGET \
    --prefix=$INSTALLDIR_NATIVE \
    --infodir=$INSTALLDIR_NATIVE_DOC/info \
    --mandir=$INSTALLDIR_NATIVE_DOC/man \
    --htmldir=$INSTALLDIR_NATIVE_DOC/html \
    --pdfdir=$INSTALLDIR_NATIVE_DOC/pdf \
    --disable-nls \
    --disable-werror \
    --enable-interwork \
    --enable-plugins \
    --with-sysroot=$INSTALLDIR_NATIVE/arm-none-eabi \
    "--with-pkgversion=$PKGVERSION"

if [ "x$DEBUG_BUILD_OPTIONS" != "x" ] ; then
    make CFLAGS="-I$BUILDDIR_NATIVE/host-libs/zlib/include $DEBUG_BUILD_OPTIONS" -j$JOBS
else
    make -j$JOBS
fi

make install

if [ "x$skip_manual" != "xyes" ]; then
	make install-html install-pdf
fi

copy_dir $INSTALLDIR_NATIVE $BUILDDIR_NATIVE/target-libs
restoreenv
popd

pushd $INSTALLDIR_NATIVE
rm -rf ./lib
popd

echo Task [III-1] /$HOST_NATIVE/gcc-first/
rm -rf $BUILDDIR_NATIVE/gcc-first && mkdir -p $BUILDDIR_NATIVE/gcc-first
pushd $BUILDDIR_NATIVE/gcc-first
$SRCDIR/$GCC/configure --target=$TARGET \
    --prefix=$INSTALLDIR_NATIVE \
    --libexecdir=$INSTALLDIR_NATIVE/lib \
    --infodir=$INSTALLDIR_NATIVE_DOC/info \
    --mandir=$INSTALLDIR_NATIVE_DOC/man \
    --htmldir=$INSTALLDIR_NATIVE_DOC/html \
    --pdfdir=$INSTALLDIR_NATIVE_DOC/pdf \
    --enable-languages=c \
    --disable-decimal-float \
    --disable-libffi \
    --disable-libgomp \
    --disable-libmudflap \
    --disable-libquadmath \
    --disable-libssp \
    --disable-libstdcxx-pch \
    --disable-nls \
    --disable-shared \
    --disable-threads \
    --disable-tls \
    --with-newlib \
    --without-headers \
    --with-gnu-as \
    --with-gnu-ld \
    --with-python-dir=share/gcc-arm-none-eabi \
    --with-sysroot=$INSTALLDIR_NATIVE/arm-none-eabi \
    ${GCC_CONFIG_OPTS}                              \
    "${GCC_CONFIG_OPTS_LCPP}"                              \
    "--with-pkgversion=$PKGVERSION" \
    ${MULTILIB_LIST}

make -j$JOBS all-gcc

make install-gcc

popd

pushd $INSTALLDIR_NATIVE
rm -rf bin/arm-none-eabi-gccbug
rm -rf ./lib/libiberty.a
rmdir include
popd

echo Task [III-2] /$HOST_NATIVE/newlib/
saveenv
prepend_path PATH $INSTALLDIR_NATIVE/bin
saveenvvar CFLAGS_FOR_TARGET '-g -O2 -ffunction-sections -fdata-sections'
rm -rf $BUILDDIR_NATIVE/newlib && mkdir -p $BUILDDIR_NATIVE/newlib
pushd $BUILDDIR_NATIVE/newlib

$SRCDIR/$NEWLIB/configure  \
    $NEWLIB_CONFIG_OPTS \
    --target=$TARGET \
    --prefix=$INSTALLDIR_NATIVE \
    --infodir=$INSTALLDIR_NATIVE_DOC/info \
    --mandir=$INSTALLDIR_NATIVE_DOC/man \
    --htmldir=$INSTALLDIR_NATIVE_DOC/html \
    --pdfdir=$INSTALLDIR_NATIVE_DOC/pdf \
    --enable-newlib-io-long-long \
    --enable-newlib-register-fini \
    --disable-newlib-supplied-syscalls \
    --disable-nls

make -j$JOBS

make install

if [ "x$skip_manual" != "xyes" ]; then
make pdf
mkdir -p $INSTALLDIR_NATIVE_DOC/pdf
cp $BUILDDIR_NATIVE/newlib/arm-none-eabi/newlib/libc/libc.pdf $INSTALLDIR_NATIVE_DOC/pdf/libc.pdf
cp $BUILDDIR_NATIVE/newlib/arm-none-eabi/newlib/libm/libm.pdf $INSTALLDIR_NATIVE_DOC/pdf/libm.pdf

make html
mkdir -p $INSTALLDIR_NATIVE_DOC/html
copy_dir $BUILDDIR_NATIVE/newlib/arm-none-eabi/newlib/libc/libc.html $INSTALLDIR_NATIVE_DOC/html/libc
copy_dir $BUILDDIR_NATIVE/newlib/arm-none-eabi/newlib/libm/libm.html $INSTALLDIR_NATIVE_DOC/html/libm
fi

popd
restoreenv

echo Task [III-3] /$HOST_NATIVE/newlib-nano/
saveenv
prepend_path PATH $INSTALLDIR_NATIVE/bin
saveenvvar CFLAGS_FOR_TARGET '-g -Os -ffunction-sections -fdata-sections'
rm -rf $BUILDDIR_NATIVE/newlib-nano && mkdir -p $BUILDDIR_NATIVE/newlib-nano
pushd $BUILDDIR_NATIVE/newlib-nano

$SRCDIR/$NEWLIB_NANO/configure  \
    $NEWLIB_CONFIG_OPTS \
    --target=$TARGET \
    --prefix=$BUILDDIR_NATIVE/target-libs \
    --disable-newlib-supplied-syscalls    \
    --enable-newlib-reent-small           \
    --disable-newlib-fvwrite-in-streamio  \
    --disable-newlib-fseek-optimization   \
    --disable-newlib-wide-orient          \
    --enable-newlib-nano-malloc           \
    --disable-newlib-unbuf-stream-opt     \
    --enable-lite-exit                    \
    --enable-newlib-global-atexit         \
    --enable-newlib-nano-formatted-io     \
    --disable-nls

make -j$JOBS
make install

popd
restoreenv

echo Task [III-4] /$HOST_NATIVE/gcc-final/
rm -f $INSTALLDIR_NATIVE/arm-none-eabi/usr
ln -s . $INSTALLDIR_NATIVE/arm-none-eabi/usr

rm -rf $BUILDDIR_NATIVE/gcc-final && mkdir -p $BUILDDIR_NATIVE/gcc-final
pushd $BUILDDIR_NATIVE/gcc-final

$SRCDIR/$GCC/configure --target=$TARGET \
    --prefix=$INSTALLDIR_NATIVE \
    --libexecdir=$INSTALLDIR_NATIVE/lib \
    --infodir=$INSTALLDIR_NATIVE_DOC/info \
    --mandir=$INSTALLDIR_NATIVE_DOC/man \
    --htmldir=$INSTALLDIR_NATIVE_DOC/html \
    --pdfdir=$INSTALLDIR_NATIVE_DOC/pdf \
    --enable-languages=c,c++ \
    --enable-plugins \
    --disable-decimal-float \
    --disable-libffi \
    --disable-libgomp \
    --disable-libmudflap \
    --disable-libquadmath \
    --disable-libssp \
    --disable-libstdcxx-pch \
    --disable-nls \
    --disable-shared \
    --disable-threads \
    --disable-tls \
    --with-gnu-as \
    --with-gnu-ld \
    --with-newlib \
    --with-headers=yes \
    --with-python-dir=share/gcc-arm-none-eabi \
    --with-sysroot=$INSTALLDIR_NATIVE/arm-none-eabi \
    $GCC_CONFIG_OPTS                                \
    "${GCC_CONFIG_OPTS_LCPP}"                              \
    "--with-pkgversion=$PKGVERSION" \
    ${MULTILIB_LIST}

# Passing USE_TM_CLONE_REGISTRY=0 via INHIBIT_LIBC_CFLAGS to disable
# transactional memory related code in crtbegin.o.
# This is a workaround. Better approach is have a t-* to set this flag via
# CRTSTUFF_T_CFLAGS
if [ "x$DEBUG_BUILD_OPTIONS" != "x" ]; then
  make -j$JOBS CXXFLAGS="$DEBUG_BUILD_OPTIONS" \
	       INHIBIT_LIBC_CFLAGS="-DUSE_TM_CLONE_REGISTRY=0"
else
  make -j$JOBS INHIBIT_LIBC_CFLAGS="-DUSE_TM_CLONE_REGISTRY=0"
fi

make install

if [ "x$skip_manual" != "xyes" ]; then
	make install-html install-pdf
fi

pushd $INSTALLDIR_NATIVE
rm -rf bin/arm-none-eabi-gccbug
LIBIBERTY_LIBRARIES=`find $INSTALLDIR_NATIVE/arm-none-eabi/lib -name libiberty.a`
for libiberty_lib in $LIBIBERTY_LIBRARIES ; do
    rm -rf $libiberty_lib
done
rm -rf ./lib/libiberty.a
rmdir include
popd

rm -f $INSTALLDIR_NATIVE/arm-none-eabi/usr
popd

echo Task [III-5] /$HOST_NATIVE/gcc-size-libstdcxx/
rm -f $BUILDDIR_NATIVE/target-libs/arm-none-eabi/usr
ln -s . $BUILDDIR_NATIVE/target-libs/arm-none-eabi/usr

rm -rf $BUILDDIR_NATIVE/gcc-size-libstdcxx && mkdir -p $BUILDDIR_NATIVE/gcc-size-libstdcxx
pushd $BUILDDIR_NATIVE/gcc-size-libstdcxx

$SRCDIR/$GCC/configure --target=$TARGET \
    --prefix=$BUILDDIR_NATIVE/target-libs \
    --enable-languages=c,c++ \
    --disable-decimal-float \
    --disable-libffi \
    --disable-libgomp \
    --disable-libmudflap \
    --disable-libquadmath \
    --disable-libssp \
    --disable-libstdcxx-pch \
    --disable-nls \
    --disable-shared \
    --disable-threads \
    --disable-tls \
    --with-gnu-as \
    --with-gnu-ld \
    --with-newlib \
    --with-headers=yes \
    --with-python-dir=share/gcc-arm-none-eabi \
    --with-sysroot=$BUILDDIR_NATIVE/target-libs/arm-none-eabi \
    $GCC_CONFIG_OPTS \
    "${GCC_CONFIG_OPTS_LCPP}"                              \
    "--with-pkgversion=$PKGVERSION" \
    ${MULTILIB_LIST}

make -j$JOBS CXXFLAGS_FOR_TARGET="-g -Os -ffunction-sections -fdata-sections -fno-exceptions"
make install

copy_multi_libs src_prefix="$BUILDDIR_NATIVE/target-libs/arm-none-eabi/lib" \
                dst_prefix="$INSTALLDIR_NATIVE/arm-none-eabi/lib"           \
                target_gcc="$BUILDDIR_NATIVE/target-libs/bin/arm-none-eabi-gcc"
popd

echo Task [III-6] /$HOST_NATIVE/gdb/
build_gdb()
{
	GDB_EXTRA_CONFIG_OPTS=$1

	rm -rf $BUILDDIR_NATIVE/gdb && mkdir -p $BUILDDIR_NATIVE/gdb
	pushd $BUILDDIR_NATIVE/gdb
	saveenv
	saveenvvar CFLAGS "$ENV_CFLAGS"
	saveenvvar CPPFLAGS "$ENV_CPPFLAGS"
	saveenvvar LDFLAGS "$ENV_LDFLAGS"

	$SRCDIR/$GDB/configure  \
	    --target=$TARGET \
	    --prefix=$INSTALLDIR_NATIVE \
	    --infodir=$INSTALLDIR_NATIVE_DOC/info \
	    --mandir=$INSTALLDIR_NATIVE_DOC/man \
	    --htmldir=$INSTALLDIR_NATIVE_DOC/html \
	    --pdfdir=$INSTALLDIR_NATIVE_DOC/pdf \
	    --disable-nls \
	    --disable-sim \
	    --disable-gas \
	    --disable-binutils \
	    --disable-ld \
	    --disable-gprof \
	    --with-libexpat \
	    --with-lzma=no \
	    --with-system-gdbinit=$INSTALLDIR_NATIVE/$HOST_NATIVE/arm-none-eabi/lib/gdbinit \
	    $GDB_CONFIG_OPTS \
	    $GDB_EXTRA_CONFIG_OPTS \
	    '--with-gdb-datadir='\''${prefix}'\''/arm-none-eabi/share/gdb' \
	    "--with-pkgversion=$PKGVERSION"

	if [ "x$DEBUG_BUILD_OPTIONS" != "x" ] ; then
	    make CFLAGS="-I$BUILDDIR_NATIVE/host-libs/zlib/include $DEBUG_BUILD_OPTIONS" -j$JOBS
	else
	    make -j$JOBS
	fi

	make install

	if [ "x$skip_manual" != "xyes" ]; then
		make install-html install-pdf
	fi

	restoreenv
	popd
}


#Always enable python support in GDB for PPA build.
if [ "x$is_ppa_release" == "xyes" ]; then
	build_gdb "--with-python=yes"
else
        #First we build GDB without python support.
	build_gdb "--with-python=no"

	#Then build gdb with python support.
	if [ "x$skip_gdb_with_python" == "xno" ]; then
		build_gdb "--with-python=yes --program-prefix=$TARGET-  --program-suffix=-py"
	fi
fi

if [ "x$is_ppa_release" != "xyes" -a "x$skip_manual" != "xyes" ]; then
echo TASK [III-7] /$HOST_NATIVE/build-manual
rm -rf $BUILDDIR_NATIVE/build-manual && mkdir -p $BUILDDIR_NATIVE/build-manual
pushd $BUILDDIR_NATIVE/build-manual
cp -r $SRCDIR/$BUILD_MANUAL/* .
echo "@set VERSION_PACKAGE ($PKGVERSION)" > version.texi
echo "@set CURRENT_YEAR  $release_year" >> version.texi
echo "@set CURRENT_MONTH $release_month" >> version.texi
echo "@set PKG_NAME $PACKAGE_NAME" >> version.texi
make clean
make
rm -rf $ROOT/How-to-build-toolchain.pdf
cp How-to-build-toolchain.pdf $ROOT
popd
fi

echo Task [III-8] /$HOST_NATIVE/pretidy/
rm -rf $INSTALLDIR_NATIVE/lib/libiberty.a
find $INSTALLDIR_NATIVE -name '*.la' -exec rm '{}' ';'

echo Task [III-9] /$HOST_NATIVE/strip_host_objects/
if [ "x$DEBUG_BUILD_OPTIONS" = "x" ] ; then
    STRIP_BINARIES=`find $INSTALLDIR_NATIVE/bin/ -name arm-none-eabi-\*`
    for bin in $STRIP_BINARIES ; do
        strip_binary strip $bin
    done

    STRIP_BINARIES=`find $INSTALLDIR_NATIVE/arm-none-eabi/bin/ -maxdepth 1 -mindepth 1 -name \*`
    for bin in $STRIP_BINARIES ; do
        strip_binary strip $bin
    done

    STRIP_BINARIES=`find $INSTALLDIR_NATIVE/lib/gcc/arm-none-eabi/$GCC_VER/ -maxdepth 1 -name \* -perm +111 -and ! -type d`
    for bin in $STRIP_BINARIES ; do
        strip_binary strip $bin
    done
fi

echo Task [III-10] /$HOST_NATIVE/strip_target_objects/
saveenv
prepend_path PATH $INSTALLDIR_NATIVE/bin
TARGET_LIBRARIES=`find $INSTALLDIR_NATIVE/arm-none-eabi/lib -name \*.a`
for target_lib in $TARGET_LIBRARIES ; do
    arm-none-eabi-objcopy -R .comment -R .note -R .debug_info -R .debug_aranges -R .debug_pubnames -R .debug_pubtypes -R .debug_abbrev -R .debug_line -R .debug_str -R .debug_ranges -R .debug_loc $target_lib || true
done

TARGET_OBJECTS=`find $INSTALLDIR_NATIVE/arm-none-eabi/lib -name \*.o`
for target_obj in $TARGET_OBJECTS ; do
    arm-none-eabi-objcopy -R .comment -R .note -R .debug_info -R .debug_aranges -R .debug_pubnames -R .debug_pubtypes -R .debug_abbrev -R .debug_line -R .debug_str -R .debug_ranges -R .debug_loc $target_obj || true
done

TARGET_LIBRARIES=`find $INSTALLDIR_NATIVE/lib/gcc/arm-none-eabi/$GCC_VER -name \*.a`
for target_lib in $TARGET_LIBRARIES ; do
    arm-none-eabi-objcopy -R .comment -R .note -R .debug_info -R .debug_aranges -R .debug_pubnames -R .debug_pubtypes -R .debug_abbrev -R .debug_line -R .debug_str -R .debug_ranges -R .debug_loc $target_lib || true
done

TARGET_OBJECTS=`find $INSTALLDIR_NATIVE/lib/gcc/arm-none-eabi/$GCC_VER -name \*.o`
for target_obj in $TARGET_OBJECTS ; do
    arm-none-eabi-objcopy -R .comment -R .note -R .debug_info -R .debug_aranges -R .debug_pubnames -R .debug_pubtypes -R .debug_abbrev -R .debug_line -R .debug_str -R .debug_ranges -R .debug_loc $target_obj || true
done
restoreenv

# PPA release needn't following steps, so we exit here.
if [ "x$is_ppa_release" == "xyes" ] ; then
  exit 0
fi

echo Task [III-11] /$HOST_NATIVE/package_tbz2/
rm -f $PACKAGEDIR/$PACKAGE_NAME_NATIVE.tar.bz2
pushd $BUILDDIR_NATIVE
rm -f $INSTALL_PACKAGE_NAME
cp $ROOT/$RELEASE_FILE $INSTALLDIR_NATIVE_DOC/
cp $ROOT/$README_FILE $INSTALLDIR_NATIVE_DOC/
cp $ROOT/$LICENSE_FILE $INSTALLDIR_NATIVE_DOC/
copy_dir_clean $SRCDIR/$SAMPLES $INSTALLDIR_NATIVE/share/gcc-arm-none-eabi/$SAMPLES
ln -s $INSTALLDIR_NATIVE $INSTALL_PACKAGE_NAME
${TAR} cjf $PACKAGEDIR/$PACKAGE_NAME_NATIVE.tar.bz2   \
    --owner=0                               \
    --group=0                               \
    --exclude=host-$HOST_NATIVE             \
    --exclude=host-$HOST_MINGW              \
    $INSTALL_PACKAGE_NAME/arm-none-eabi     \
    $INSTALL_PACKAGE_NAME/bin               \
    $INSTALL_PACKAGE_NAME/lib               \
    $INSTALL_PACKAGE_NAME/share             
rm -f $INSTALL_PACKAGE_NAME
popd

# skip building mingw32 toolchain if "--skip_mingw32" specified
# this huge if statement controls all $BUILDDIR_MINGW tasks till "task [IV-8]"
if [ "x$skip_mingw32" != "xyes" ] ; then
saveenv
saveenvvar CC_FOR_BUILD gcc
saveenvvar CC $HOST_MINGW_TOOL-gcc
saveenvvar CXX $HOST_MINGW_TOOL-g++
saveenvvar AR $HOST_MINGW_TOOL-ar
saveenvvar RANLIB $HOST_MINGW_TOOL-ranlib
saveenvvar STRIP $HOST_MINGW_TOOL-strip
saveenvvar NM $HOST_MINGW_TOOL-nm

echo Task [IV-0] /$HOST_MINGW/host_unpack/
rm -rf $BUILDDIR_MINGW/tools-$OBJ_SUFFIX_NATIVE && mkdir $BUILDDIR_MINGW/tools-$OBJ_SUFFIX_NATIVE
pushd $BUILDDIR_MINGW/tools-$OBJ_SUFFIX_NATIVE
ln -s . $INSTALL_PACKAGE_NAME
tar xf $PACKAGEDIR/$PACKAGE_NAME_NATIVE.tar.bz2 --bzip2
rm $INSTALL_PACKAGE_NAME
popd

echo Task [IV-1] /$HOST_MINGW/binutils/
prepend_path PATH $BUILDDIR_MINGW/tools-$OBJ_SUFFIX_NATIVE/bin
rm -rf $BUILDDIR_MINGW/binutils && mkdir -p $BUILDDIR_MINGW/binutils
pushd $BUILDDIR_MINGW/binutils
saveenv
saveenvvar CFLAGS "-I$BUILDDIR_MINGW/host-libs/zlib/include -O2"
saveenvvar CPPFLAGS "-I$BUILDDIR_MINGW/host-libs/zlib/include"
saveenvvar LDFLAGS "-L$BUILDDIR_MINGW/host-libs/zlib/lib"
$SRCDIR/$BINUTILS/configure --build=$BUILD \
    --host=$HOST_MINGW \
    --target=$TARGET \
    --prefix=$INSTALLDIR_MINGW \
    --infodir=$INSTALLDIR_MINGW_DOC/info \
    --mandir=$INSTALLDIR_MINGW_DOC/man \
    --htmldir=$INSTALLDIR_MINGW_DOC/html \
    --pdfdir=$INSTALLDIR_MINGW_DOC/pdf \
    --disable-nls \
    --enable-plugins \
    --with-sysroot=$INSTALLDIR_MINGW/arm-none-eabi \
    "--with-pkgversion=$PKGVERSION"

if [ "x$DEBUG_BUILD_OPTIONS" != "x" ] ; then
    make CFLAGS="-I$BUILDDIR_MINGW/host-libs/zlib/include $DEBUG_BUILD_OPTIONS" -j$JOBS
else
    make -j$JOBS
fi

make install

if [ "x$skip_manual" != "xyes" ]; then
	make install-html install-pdf
fi

restoreenv
popd

pushd $INSTALLDIR_MINGW
rm -rf ./lib
popd

echo Task [IV-2] /$HOST_MINGW/copy_libs/
if [ "x$skip_manual" != "xyes" ]; then
copy_dir $BUILDDIR_MINGW/tools-$OBJ_SUFFIX_NATIVE/share/doc/gcc-arm-none-eabi/html $INSTALLDIR_MINGW_DOC/html
copy_dir $BUILDDIR_MINGW/tools-$OBJ_SUFFIX_NATIVE/share/doc/gcc-arm-none-eabi/pdf $INSTALLDIR_MINGW_DOC/pdf
fi
copy_dir $BUILDDIR_MINGW/tools-$OBJ_SUFFIX_NATIVE/arm-none-eabi/lib $INSTALLDIR_MINGW/arm-none-eabi/lib
copy_dir $BUILDDIR_MINGW/tools-$OBJ_SUFFIX_NATIVE/arm-none-eabi/include $INSTALLDIR_MINGW/arm-none-eabi/include
copy_dir $BUILDDIR_MINGW/tools-$OBJ_SUFFIX_NATIVE/arm-none-eabi/include/c++ $INSTALLDIR_MINGW/arm-none-eabi/include/c++
copy_dir $BUILDDIR_MINGW/tools-$OBJ_SUFFIX_NATIVE/lib/gcc/arm-none-eabi $INSTALLDIR_MINGW/lib/gcc/arm-none-eabi

echo Task [IV-3] /$HOST_MINGW/gcc-final/
saveenv
saveenvvar AR_FOR_TARGET $TARGET-ar
saveenvvar NM_FOR_TARGET $TARGET-nm
saveenvvar OBJDUMP_FOR_TARET $TARGET-objdump
saveenvvar STRIP_FOR_TARGET $TARGET-strip
saveenvvar CC_FOR_TARGET $TARGET-gcc
saveenvvar GCC_FOR_TARGET $TARGET-gcc
saveenvvar CXX_FOR_TARGET $TARGET-g++

pushd $INSTALLDIR_MINGW/arm-none-eabi/
rm -f usr
ln -s . usr
popd
rm -rf $BUILDDIR_MINGW/gcc && mkdir -p $BUILDDIR_MINGW/gcc
pushd $BUILDDIR_MINGW/gcc
$SRCDIR/$GCC/configure --build=$BUILD --host=$HOST_MINGW --target=$TARGET \
    --prefix=$INSTALLDIR_MINGW \
    --libexecdir=$INSTALLDIR_MINGW/lib \
    --infodir=$INSTALLDIR_MINGW_DOC/info \
    --mandir=$INSTALLDIR_MINGW_DOC/man \
    --htmldir=$INSTALLDIR_MINGW_DOC/html \
    --pdfdir=$INSTALLDIR_MINGW_DOC/pdf \
    --enable-languages=c,c++ \
    --disable-decimal-float \
    --disable-libffi \
    --disable-libgomp \
    --disable-libmudflap \
    --disable-libquadmath \
    --disable-libssp \
    --disable-libstdcxx-pch \
    --disable-nls \
    --disable-shared \
    --disable-threads \
    --disable-tls \
    --with-gnu-as \
    --with-gnu-ld \
    --with-headers=yes \
    --with-newlib \
    --with-python-dir=share/gcc-arm-none-eabi \
    --with-sysroot=$INSTALLDIR_MINGW/arm-none-eabi \
    --with-libiconv-prefix=$BUILDDIR_MINGW/host-libs/usr \
    --with-gmp=$BUILDDIR_MINGW/host-libs/usr \
    --with-mpfr=$BUILDDIR_MINGW/host-libs/usr \
    --with-mpc=$BUILDDIR_MINGW/host-libs/usr \
    --with-isl=$BUILDDIR_MINGW/host-libs/usr \
    --with-cloog=$BUILDDIR_MINGW/host-libs/usr \
    --with-libelf=$BUILDDIR_MINGW/host-libs/usr \
    "--with-host-libstdcxx=-static-libgcc -Wl,-Bstatic,-lstdc++,-Bdynamic -lm" \
    "--with-pkgversion=$PKGVERSION" \
    ${MULTILIB_LIST}

if [ "x$DEBUG_BUILD_OPTIONS" != "x" ]; then
  make -j$JOBS CXXFLAGS="$DEBUG_BUILD_OPTIONS" all-gcc
else
  make -j$JOBS all-gcc
fi

make  install-gcc

if [ "x$skip_manual" != "xyes" ]; then
	make install-html-gcc install-pdf-gcc
fi
popd

pushd $INSTALLDIR_MINGW
rm -rf bin/arm-none-eabi-gccbug
rmdir include
popd

copy_dir $BUILDDIR_MINGW/tools-$OBJ_SUFFIX_NATIVE/lib/gcc/arm-none-eabi $INSTALLDIR_MINGW/lib/gcc/arm-none-eabi
rm -rf $INSTALLDIR_MINGW/arm-none-eabi/usr
rm -rf $INSTALLDIR_MINGW/lib/gcc/arm-none-eabi/*/plugin
find $INSTALLDIR_MINGW -executable -and -not -type d -and -not -name \*.exe \
  -and -not -name liblto_plugin-0.dll -exec rm -f \{\} \;
restoreenv

echo Task [IV-4] /$HOST_MINGW/gdb/
build_mingw_gdb()
{
	MINGW_GDB_CONF_OPTS=$1
	rm -rf $BUILDDIR_MINGW/gdb && mkdir -p $BUILDDIR_MINGW/gdb
	pushd $BUILDDIR_MINGW/gdb
	saveenv
	saveenvvar CFLAGS "-I$BUILDDIR_MINGW/host-libs/zlib/include -O2"
	saveenvvar CPPFLAGS "-I$BUILDDIR_MINGW/host-libs/zlib/include"
	saveenvvar LDFLAGS "-L$BUILDDIR_MINGW/host-libs/zlib/lib"
	$SRCDIR/$GDB/configure --build=$BUILD \
	    --host=$HOST_MINGW \
	    --target=$TARGET \
	    --prefix=$INSTALLDIR_MINGW \
	    --infodir=$INSTALLDIR_MINGW_DOC/info \
	    --mandir=$INSTALLDIR_MINGW_DOC/man \
	    --htmldir=$INSTALLDIR_MINGW_DOC/html \
	    --pdfdir=$INSTALLDIR_MINGW_DOC/pdf \
	    --disable-nls \
	    --disable-sim \
	    --disable-gas \
	    --disable-binutils \
	    --disable-ld \
	    --disable-gprof \
	    --with-lzma=no \
	    $MINGW_GDB_CONF_OPTS \
	    --with-libexpat=$BUILDDIR_MINGW/host-libs/usr \
	    --with-libiconv-prefix=$BUILDDIR_MINGW/host-libs/usr \
	    --with-system-gdbinit=$INSTALLDIR_MINGW/$HOST_MINGW/arm-none-eabi/lib/gdbinit \
	    '--with-gdb-datadir='\''${prefix}'\''/arm-none-eabi/share/gdb' \
	    "--with-pkgversion=$PKGVERSION"

	if [ "x$DEBUG_BUILD_OPTIONS" != "x" ] ; then
	    make CFLAGS="-I$BUILDDIR_MINGW/host-libs/zlib/include $DEBUG_BUILD_OPTIONS" -j$JOBS
	else
	    make -j$JOBS
	fi

	make install
	if [ "x$skip_manual" != "xyes" ]; then
		make install-html install-pdf
	fi

	restoreenv
	popd
}

build_mingw_gdb "--with-python=no"

if [ "x$skip_mingw32_gdb_with_python" == "xno" ]; then
	build_mingw_gdb "--with-python=$build_tools_abs_path/python-config.sh --program-suffix=-py --program-prefix=$TARGET-"
fi

echo Task [IV-5] /$HOST_MINGW/pretidy/
pushd $INSTALLDIR_MINGW
rm -rf ./lib/libiberty.a
rm -rf $INSTALLDIR_MINGW_DOC/info
rm -rf $INSTALLDIR_MINGW_DOC/man

find $INSTALLDIR_MINGW -name '*.la' -exec rm '{}' ';'

echo Task [IV-6] /$HOST_MINGW/strip_host_objects/
STRIP_BINARIES=`find $INSTALLDIR_MINGW/bin/ -name arm-none-eabi-\*.exe`
if [ "x$DEBUG_BUILD_OPTIONS" = "x" ] ; then
    for bin in $STRIP_BINARIES ; do
        strip_binary $HOST_MINGW_TOOL-strip $bin
    done

    STRIP_BINARIES=`find $INSTALLDIR_MINGW/arm-none-eabi/bin/ -maxdepth 1 -mindepth 1 -name \*.exe`
    for bin in $STRIP_BINARIES ; do
        strip_binary $HOST_MINGW_TOOL-strip $bin
    done

    STRIP_BINARIES=`find $INSTALLDIR_MINGW/lib/gcc/arm-none-eabi/$GCC_VER/ -name \*.exe`
    for bin in $STRIP_BINARIES ; do
        strip_binary $HOST_MINGW_TOOL-strip $bin
    done
fi

echo Task [IV-7] /$HOST_MINGW/installation/
rm -f $PACKAGEDIR/$PACKAGE_NAME_MINGW.exe
pushd $BUILDDIR_MINGW
rm -f $INSTALL_PACKAGE_NAME
cp $ROOT/$RELEASE_FILE $INSTALLDIR_MINGW_DOC/
cp $ROOT/$README_FILE $INSTALLDIR_MINGW_DOC/
cp $ROOT/$LICENSE_FILE $INSTALLDIR_MINGW_DOC/
copy_dir_clean $SRCDIR/$SAMPLES $INSTALLDIR_MINGW/share/gcc-arm-none-eabi/$SAMPLES
flip -m $INSTALLDIR_MINGW_DOC/$RELEASE_FILE
flip -m $INSTALLDIR_MINGW_DOC/$README_FILE
flip -m -b $INSTALLDIR_MINGW_DOC/$LICENSE_FILE
flip -m $INSTALLDIR_MINGW/share/gcc-arm-none-eabi/$SAMPLES_DOS_FILES
rm -rf $INSTALLDIR_MINGW/include
ln -s $INSTALLDIR_MINGW $INSTALL_PACKAGE_NAME

$SRCDIR/$INSTALLATION/build_win_pkg.sh --package=$INSTALL_PACKAGE_NAME --release_ver=$RELEASEVER --date=$RELEASEDATE
mv $SRCDIR/$INSTALLATION/build.log $SRCDIR/$INSTALLATION/build.installjammer.log
mv $SRCDIR/$INSTALLATION/output/$PACKAGE_NAME_MINGW.exe $PACKAGEDIR/$PACKAGE_NAME_MINGW.installjammer.exe

cp $SRCDIR/$INSTALLATION/gccvar.bat $INSTALLDIR_MINGW/bin
mkdir -p $SRCDIR/$INSTALLATION/output
makensis -DBaseDir=$INSTALLDIR_MINGW  \
         -DAppName="$APPNAME" \
         -DAppNameStr="$PKGVERSION"   \
         -DPackageName=$PACKAGE_NAME_MINGW   \
         -DInstallDirBase="$INSTALLBASE"   \
         -DInstallDirVer="$GCC_VER_SHORT $RELEASEVER" \
         "-XOutFile $SRCDIR/$INSTALLATION/output/$PACKAGE_NAME_MINGW.exe"    \
         $SRCDIR/$INSTALLATION/arm-none-eabi-gnu-tools.nsi

cp -rf $SRCDIR/$INSTALLATION/output/$PACKAGE_NAME_MINGW.exe $PACKAGEDIR/
rm -f $INSTALL_PACKAGE_NAME
popd
restoreenv

echo Task [IV-8] /Package toolchain in zip format/
pushd $INSTALLDIR_MINGW
rm -f $PACKAGEDIR/$PACKAGE_NAME_MINGW.zip
zip -r9 $PACKAGEDIR/$PACKAGE_NAME_MINGW.zip .
popd
fi #end of if [ "x$skip_mingw32" != "xyes" ] ;

echo Task [V-0] /package_sources/
pushd $PACKAGEDIR
rm -rf $PACKAGE_NAME && mkdir -p $PACKAGE_NAME/src
cp -f $SRCDIR/$CLOOG_PACK $PACKAGE_NAME/src/
cp -f $SRCDIR/$EXPAT_PACK $PACKAGE_NAME/src/
cp -f $SRCDIR/$GMP_PACK $PACKAGE_NAME/src/
cp -f $SRCDIR/$LIBELF_PACK $PACKAGE_NAME/src/
cp -f $SRCDIR/$LIBICONV_PACK $PACKAGE_NAME/src/
cp -f $SRCDIR/$MPC_PACK $PACKAGE_NAME/src/
cp -f $SRCDIR/$MPFR_PACK $PACKAGE_NAME/src/
cp -f $SRCDIR/$ISL_PACK $PACKAGE_NAME/src/
cp -f $SRCDIR/$ZLIB_PACK $PACKAGE_NAME/src/
pack_dir_clean $SRCDIR $BINUTILS $PACKAGE_NAME/src/$BINUTILS.tar.bz2
pack_dir_clean $SRCDIR $GCC $PACKAGE_NAME/src/$GCC.tar.bz2
pack_dir_clean $SRCDIR $GDB $PACKAGE_NAME/src/$GDB.tar.bz2 \
  --exclude="gdb/testsuite/config/qemu.exp" --exclude="sim"
pack_dir_clean $SRCDIR $NEWLIB $PACKAGE_NAME/src/$NEWLIB.tar.bz2
pack_dir_clean $SRCDIR $SAMPLES $PACKAGE_NAME/src/$SAMPLES.tar.bz2
pack_dir_clean $SRCDIR $BUILD_MANUAL $PACKAGE_NAME/src/$BUILD_MANUAL.tar.bz2
if [ "x$skip_mingw32" != "xyes" ] ; then
    pack_dir_clean $SRCDIR $INSTALLATION \
      $PACKAGE_NAME/src/$INSTALLATION.tar.bz2 \
      --exclude=build.log --exclude=output
fi
cp $ROOT/$RELEASE_FILE $PACKAGE_NAME/
cp $ROOT/$README_FILE $PACKAGE_NAME/
cp $ROOT/$LICENSE_FILE $PACKAGE_NAME/
cp $ROOT/$BUILD_MANUAL_FILE $PACKAGE_NAME/
cp $ROOT/build-common.sh $PACKAGE_NAME/
cp $ROOT/build-prerequisites.sh $PACKAGE_NAME/
cp $ROOT/build-toolchain.sh $PACKAGE_NAME/
tar cjf $PACKAGE_NAME-src.tar.bz2 $PACKAGE_NAME
rm -rf $PACKAGE_NAME
popd

echo Task [V-1] /md5_checksum/
pushd $PACKAGEDIR
rm -rf md5.txt
$MD5 $PACKAGE_NAME_NATIVE.tar.bz2     >>md5.txt
if [ "x$skip_mingw32" != "xyes" ] ; then
    $MD5 $PACKAGE_NAME_MINGW.exe         >>md5.txt
    $MD5 $PACKAGE_NAME_MINGW.installjammer.exe >>md5.txt
    $MD5 $PACKAGE_NAME_MINGW.zip         >>md5.txt
fi
$MD5 $PACKAGE_NAME-src.tar.bz2 >>md5.txt
popd
