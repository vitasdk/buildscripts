## VitaSDK. How to build.

```
apt-get install cmake git build-essential autoconf texinfo
```

### Native compilation.

* Linux host -> Linux toolchain.
* OSX host -> OSX toolchain.

``` sh
mkdir build
cd build
cmake ..
make -j4
```

### Cross compilation.

* Linux host -> mingw32 toolchain

``` sh
mkdir build
cd build
cmake .. -DCMAKE_TOOLCHAIN_FILE=toolchain-x86_64-w64-mingw32.cmake
make -j4
```

### Cmake command-line options

You can pass then on the cmake phrase like this `cmake .. -DFOO=ON`.

If you want to fetch an specific revision of a part of the toolchain
then you can pass the branch/tag/id from the command line. The available
values are `NEWLIB_TAG`, `TOOLCHAIN_TAG`, `PTHREAD_TAG`, `HEADERS_TAG`
and `SAMPLES_TAG`. For example:

``` sh
cmake /path/to/cmakelists -DNEWLIB_TAG=0254c2dc0c2686f69580030af3cacc795c94d616
```

This will configure the vitasdk to use that newlib commit instead of the `vita` branch.

If you need to change the download directory used for the tarballs then do the following,
for example:

``` sh
cmake /path/to/cmakelists -DDOWNLOAD_DIR=$HOME/vitasdk_tarballs
```

The remote repositories won't be checked for updates if you run `make` again.
If you don't want this behaviour then pass -DOFFLINE=NO to the cmake command line.
This is only available if your CMake installation is 3.2.0 or greater, else it will always
check for updates the next time you run make.

To change the default installation path a path to CMAKE_INSTALL_PREFIX, for example:

``` sh
cmake /path/to/cmakelists -DCMAKE_INSTALL_PREFIX=$HOME/vitasdk
```

If you want to create a tarball of the sdk then run the following command:

``` sh
make tarball
```