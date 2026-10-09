# syntax=docker/dockerfile:1
#
# simplenotes-server in an image of its own: the server, its model, and the
# shared libraries it runs on, nothing else (no shell, no package manager).
# Built from source, as ODataKit's images are: the GNUstep stack (Foundation
# only), FreeCoreData with its PostgreSQL and MySQL stores, ODataKit and
# TopoText, at the pins CI tests.
#
#   docker build -f Docker/server.Dockerfile -t simplenotes-server .
#   docker run -p 8080:8080 -v notes:/data simplenotes-server
#
# Its settings are environment variables (SN_ and the setting's name):
#   SN_STORE_URL     /data/notes.sqlite (default), or a database's URL
#   SN_STORE_TYPE    SQLite (default), PostgreSQL, MySQL, MariaDB
#   SN_SERVICE_ROOT  the public URL it is reached at (behind a proxy)
#   SN_PORT          8080
#   ...and every other of HTTPServerKit's (HS_ settings, SN_ here).
#
# Not Alpine: GNUstep's runtime (libobjc2, libdispatch, gnustep-base) is
# built and tested on glibc, and what makes an image of it big is ICU's
# data, the same on musl. The final stage is FROM scratch: the libraries are
# glibc's and the stack's, copied from where they were built.

ARG UBUNTU=24.04

FROM ubuntu:${UBUNTU} AS toolchain
ARG DEBIAN_FRONTEND=noninteractive
# Through caching proxies that answer with stale indexes: no pipelining, no
# proxy caches, retries (as ODataKit's images).
RUN printf 'Acquire::http::No-Cache "true";\nAcquire::BrokenProxy "true";\nAcquire::http::Pipeline-Depth "0";\nAcquire::Retries "3";\n' \
      > /etc/apt/apt.conf.d/99-simplenotes
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates git make cmake patch pkg-config clang lld binutils \
      libgnutls28-dev libffi-dev libicu-dev libxml2-dev libxslt1-dev libssl-dev zlib1g-dev \
      libcurl4-gnutls-dev libgmp-dev libsqlite3-dev libpq-dev libmariadb-dev libavahi-compat-libdnssd-dev \
      tzdata \
 && rm -rf /var/lib/apt/lists/* \
 # The gnustep-2.0 runtime needs ld.gold or lld.
 && update-alternatives --install /usr/bin/ld ld /usr/bin/ld.lld 10
ENV PREFIX=/opt/gnustep \
    CC=clang CXX=clang++ \
    LIBRARY_COMBO=ng-gnu-gnu RUNTIME_VERSION=gnustep-2.0 \
    COMPONENTS="libobjc2 libdispatch tools-make libs-base"

# The stack: gnustep-patches' build, at CI's pin.
FROM toolchain AS stack
ARG GNUSTEP_PATCHES_REF=1eda55d84efa24990a54b67bbbd6e3b785fc1ba9
RUN set -e; \
    mkdir -p /tmp/src/gnustep-patches && cd /tmp/src/gnustep-patches; \
    git init -q && git remote add origin https://github.com/ashalkhakov/gnustep-patches.git; \
    git fetch -q --depth 1 origin "$GNUSTEP_PATCHES_REF" && git checkout -q FETCH_HEAD; \
    SOURCES=/tmp/src/gnustep Scripts/build-gnustep.sh; \
    rm -rf /tmp/src

# FreeCoreData and ODataKit, at CI's pins.
FROM stack AS libraries
ARG FREECOREDATA_REF=524709592bf8670dab363d4c00d70eff4aa51e55
ARG ODATAKIT_REF=6a381a9ced6c7937390c1cdce937f47c00798a71
SHELL ["/bin/bash", "-c"]
RUN set -e; . /opt/gnustep/System/Library/Makefiles/GNUstep.sh; export LD_LIBRARY_PATH=/opt/gnustep/lib:$LD_LIBRARY_PATH; \
    mkdir -p /tmp/src/FreeCoreData && cd /tmp/src/FreeCoreData; \
    git init -q && git remote add origin https://github.com/ashalkhakov/FreeCoreData.git; \
    git fetch -q --depth 1 origin "$FREECOREDATA_REF" && git checkout -q FETCH_HEAD; \
    make -j"$(nproc)" && make install; \
    make -C Tools/momc && make -C Tools/momc install; \
    make -C Backends/PostgreSQL && make -C Backends/PostgreSQL install; \
    make -C Backends/MySQL && make -C Backends/MySQL install; \
    mkdir -p /tmp/src/ODataKit && cd /tmp/src/ODataKit; \
    git init -q && git remote add origin https://github.com/ashalkhakov/ODataKit.git; \
    git fetch -q --depth 1 origin "$ODATAKIT_REF" && git checkout -q FETCH_HEAD; \
    make -j"$(nproc)" && make install; \
    cd / && rm -rf /tmp/src

# TopoText and the server.
FROM libraries AS build
ARG VERSION=0.0.0
COPY . /usr/src/topotext
WORKDIR /usr/src/topotext
RUN set -e; . /opt/gnustep/System/Library/Makefiles/GNUstep.sh; export LD_LIBRARY_PATH=/opt/gnustep/lib:$LD_LIBRARY_PATH; \
    rm -rf build obj Examples/SimpleNotes/obj; \
    make -j"$(nproc)" && make install; \
    make -C Examples/SimpleNotes SN_SERVER_ONLY=yes -j"$(nproc)"

# What the server needs at run time, at the paths it was built with
# (Docker/collect-server.sh), into /rootfs.
FROM build AS collect
RUN Docker/collect-server.sh /rootfs

FROM scratch AS server
COPY --from=collect /rootfs /
ENV LD_LIBRARY_PATH=/opt/gnustep/lib:/opt/gnustep/Local/Library/Libraries:/opt/gnustep/System/Library/Libraries \
    HOME=/data TZ=UTC \
    SN_PORT=8080 SN_LOCALHOST=NO \
    SN_STORE_URL=/data/notes.sqlite \
    SN_ACCESS_LOG=json \
    CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
USER 10001:10001
WORKDIR /data
VOLUME /data
EXPOSE 8080
ENTRYPOINT ["/app/simplenotes-server"]
