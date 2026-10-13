# syntax=docker/dockerfile:1
#
# simplenotes-server in an image of its own: the server, its model, and the
# shared libraries it runs on, nothing else (no shell, no package manager).
# Built on gnustep-patches' GNUstep stack image, from source: FreeCoreData
# with its PostgreSQL and MySQL stores, ODataKit and TopoText, at the pins CI
# tests.
#
#   docker build -f Docker/server.Dockerfile -t simplenotes-server .
#   docker run -p 8080:8080 -v notes:/data simplenotes-server
#
# Its settings are environment variables (SN_ and the setting's name):
#   SN_STORE_URL     /data/notes.sqlite (default), or a database's URL
#   SN_STORE_TYPE    SQLite (default), PostgreSQL, MySQL, MariaDB
#   SN_SERVICE_ROOT  the public URL it is reached at (behind a proxy)
#   SN_PORT          8080
#   SN_MAX_PAGE_BYTES  JSON a response at most (4 MB): what one holds is built in memory
#   SN_MAX_PAGE_SIZE   rows a response at most (default: no limit but the bytes')
#   ...and every other of HTTPServerKit's (HS_ settings, SN_ here).
#
# Not Alpine: GNUstep's runtime (libobjc2, libdispatch, gnustep-base) is
# built and tested on glibc, and what makes an image of it big is ICU's
# data, the same on musl. The final stage is FROM scratch: the libraries are
# glibc's and the stack's, copied from where they were built.

# The patched GNUstep stack, gnustep-patches' image (its newest; --build-arg
# STACK=ghcr.io/ashalkhakov/gnustep:<version> for another), and what the
# server links beyond it: FreeCoreData's SQLite, PostgreSQL and MySQL clients.
ARG STACK=ghcr.io/ashalkhakov/gnustep:latest

FROM ${STACK} AS stack
ARG DEBIAN_FRONTEND=noninteractive
# Through caching proxies that answer with stale indexes: no pipelining, no
# proxy caches, retries (as ODataKit's images).
RUN printf 'Acquire::http::No-Cache "true";\nAcquire::BrokenProxy "true";\nAcquire::http::Pipeline-Depth "0";\nAcquire::Retries "3";\n' \
      > /etc/apt/apt.conf.d/99-simplenotes \
 && apt-get update && apt-get install -y --no-install-recommends \
      libsqlite3-dev libpq-dev libmariadb-dev tzdata \
 && rm -rf /var/lib/apt/lists/*
COPY .github/pins.env /tmp/pins.env

# FreeCoreData and ODataKit, at .github/pins.env's commits.
FROM stack AS libraries
ARG FREECOREDATA_REF
ARG ODATAKIT_REF
SHELL ["/bin/bash", "-c"]
RUN set -e; fcd=$FREECOREDATA_REF; odk=$ODATAKIT_REF; . /tmp/pins.env; \
    FREECOREDATA_REF=${fcd:-$FREECOREDATA_REF}; ODATAKIT_REF=${odk:-$ODATAKIT_REF}; \
    . /opt/gnustep/System/Library/Makefiles/GNUstep.sh; export LD_LIBRARY_PATH=/opt/gnustep/lib:$LD_LIBRARY_PATH; \
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
