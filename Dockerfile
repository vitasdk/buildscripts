# First stage of Dockerfile
FROM alpine:latest

COPY . /src

RUN apk add build-base cmake git bash autoconf texinfo patch pkgconfig
RUN cd /src && mkdir build && cd build && cmake .. && make -j2

# Second stage of Dockerfile
FROM alpine:latest  

ENV VITASDK /home/user/vitasdk
ENV PATH ${VITASDK}/bin:$PATH

COPY --from=0 /src/build/vitasdk ${VITASDK}