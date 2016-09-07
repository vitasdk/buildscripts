# How to build the toolchain

1. Read the pdf
2. Download & untar all deps
3. Replace `src/newlib` with a version for the Vita: https://github.com/vitasdk/newlib
4. Clone https://github.com/vitasdk/vita-toolchain to `src/vita-toolchain`
5. Clone https://github.com/vitasdk/vita-headers to `src/vita-headers`
6. Clone https://github.com/vitasdk/pthread-embedded to `src/pthread-embedded`
7. Download http://www.digip.org/jansson/releases/jansson-2.7.tar.gz and untar to `src/jansson-2.7`
8. Download http://nih.at/libzip/libzip-1.1.3.tar.gz and untar to `src/libzip-1.1.3`
9. Apply `vita.patch`: `patch -p1 < vita.patch`
10. Build
11. ...
12. Ask for help in #vitasdk @ freenode because this never works right

If you're building on Ubuntu 8.10, `git` from its repos won't work. You can use `wget` to download dependencies instead. (e.g. https://github.com/vitasdk/vita-headers/archive/master.zip)
