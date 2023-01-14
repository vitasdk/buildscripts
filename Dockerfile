# First stage of Dockerfile
FROM alpine:3.12

COPY . /src

RUN apk add build-base cmake git bash autoconf automake libtool texinfo patch pkgconfig python3 && ln -sf python3 /usr/bin/python
RUN cd /src && mkdir build && cd build && cmake .. && make -j$(nproc)

# Second stage of Dockerfile
FROM alpine:latest

ENV VITASDK /usr/local/vitasdk
ENV PATH ${VITASDK}/bin:$PATH

RUN adduser -D user &&\
    echo "export VITASDK=${VITASDK}" > /etc/profile.d/vitasdk.sh && \
    echo 'export PATH=$PATH:$VITASDK/bin'  >> /etc/profile.d/vitasdk.sh

COPY --from=0 --chown=user /src/build/vitasdk ${VITASDK}
