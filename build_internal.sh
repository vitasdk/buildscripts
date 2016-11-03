#!/bin/bash

mkdir build
cd build
cmake .. -DNEWLIB_TAG=patch-1
make -j4 tarball
