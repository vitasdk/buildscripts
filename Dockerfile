FROM ubuntu:trusty
MAINTAINER codestation404@gmail.com

RUN apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y cmake git build-essential autoconf texinfo && \
  rm -rf /var/lib/apt/lists/*

ENV OUTPUT_DIR=/out

RUN adduser --disabled-login --gecos 'user' user && passwd -d user

USER user
WORKDIR /home/user

RUN mkdir /home/user/.ssh && chmod 700 /home/user/.ssh -R && \
  ssh-keyscan github.com >> /home/user/.ssh/known_hosts

RUN git clone https://github.com/codestation/vitasdk-cmake

RUN mkdir build
WORKDIR /home/user/build
RUN cmake /home/user/vitasdk-cmake
RUN make -j4
RUN mv vitasdk /home/user

WORKDIR /home/user
RUN echo VITASDK=/home/user/vitasdk >> /home/user/.bashrc
RUN echo PATH=\$VITASDK/bin:\$PATH >> /home/user/.bashrc

RUN rm -rf /home/user/build /home/user/vitasdk-cmake
