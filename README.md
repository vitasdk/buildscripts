## VitaSDK. How to build.

```
apt-get install cmake git build-essential autoconf
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
