# First stage of Dockerfile
FROM alpine:latest AS build

RUN apk add --no-cache build-base cmake git bash autoconf automake libtool texinfo patch pkgconfig python3 ccache \
    && ln -sf python3 /usr/bin/python

COPY . /src

# Use ccache and parallel build
RUN --mount=type=cache,target=/root/.ccache \
    cd /src && mkdir -p build && cd build && \
    cmake -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache .. && \
    make -j$(nproc)

# Second stage of Dockerfile
FROM alpine:latest

# Instalar dependencias en tiempo de ejecución para que la imagen sea útil
RUN apk add --no-cache bash git make cmake python3

ENV VITASDK /usr/local/vitasdk
ENV PATH ${VITASDK}/bin:$PATH

RUN adduser -D user &&\
    echo "export VITASDK=${VITASDK}" > /etc/profile.d/vitasdk.sh && \
    echo 'export PATH=$PATH:$VITASDK/bin'  >> /etc/profile.d/vitasdk.sh

COPY --from=build --chown=user /src/build/vitasdk ${VITASDK}
