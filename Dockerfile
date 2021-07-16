# First stage of Dockerfile
FROM alpine:3.12

COPY . /src

RUN apk add build-base cmake git bash autoconf texinfo patch pkgconfig python3 && ln -sf python3 /usr/bin/python
RUN cd /src && mkdir build && cd build && cmake .. && make -j$(nproc)

# Second stage of Dockerfile
FROM alpine:latest  

ENV VITASDK /home/user/vitasdk
ENV PATH ${VITASDK}/bin:$PATH

COPY --from=0 /src/build/vitasdk ${VITASDK}
