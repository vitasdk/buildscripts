# First stage of Dockerfile
FROM alpine:latest AS build

RUN apk add build-base cmake git bash autoconf automake libtool texinfo patch pkgconfig python3 && ln -sf python3 /usr/bin/python

COPY . /src

RUN cd /src && mkdir build && cd build && cmake .. && make 
# -j$(nproc)

# Second stage of Dockerfile
FROM alpine:latest

# Instalar dependencias en tiempo de ejecución para que la imagen sea útil
RUN apk add --no-cache bash git make cmake python3

ENV VITASDK /usr/local/vitasdk
ENV PATH ${VITASDK}/bin:$PATH

RUN adduser -D user &&\
    echo "export VITASDK=${VITASDK}" > /etc/profile.d/vitasdk.sh && \
    echo 'export PATH=$PATH:$VITASDK/bin'  >> /etc/profile.d/vitasdk.sh

COPY --from=0 --chown=user /src/build/vitasdk ${VITASDK}
