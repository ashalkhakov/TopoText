# syntax=docker/dockerfile:1
#
# TopoText and SimpleNotes on GNUstep, built and tested in ODataKit's sdk
# image (gnustep-patches' GNUstep stack image, with FreeCoreData and ODataKit
# installed; ODataKit's Docker/Dockerfile):
#
#   docker build -f Docker/Dockerfile --target check .
#   docker build -f Docker/Dockerfile --target check --build-context freecoredata=../FreeCoreData .
#   docker build -f Docker/Dockerfile --target sdk -t topotext-sdk .
#
# SDK: that image, built from a checkout of ODataKit
#   (docker build -f Docker/Dockerfile --target sdk -t odatakit-sdk . there)
# or as a release publishes it (ghcr.io/ashalkhakov/odatakit-sdk:<version>).

ARG SDK=odatakit-sdk:latest

# FreeCoreData, rebuilt over the sdk's: a commit of it, or a checkout of
# one's own (--build-context freecoredata=../FreeCoreData).
# The commit is .github/pins.env's (--build-arg FREECOREDATA_REF=... for another).
FROM alpine/git AS freecoredata-git
ARG FREECOREDATA_REF
COPY .github/pins.env /tmp/pins.env
RUN set -e; ref=$FREECOREDATA_REF; . /tmp/pins.env; FREECOREDATA_REF=${ref:-$FREECOREDATA_REF}; \
    git clone -q https://github.com/ashalkhakov/FreeCoreData.git /src && cd /src && git checkout -q "$FREECOREDATA_REF"
FROM scratch AS freecoredata
COPY --from=freecoredata-git /src /

# The sdk is gnustep-patches' stack (AppKit, the Eau theme and all) with
# FreeCoreData and ODataKit installed; FreeCoreData again, at this pin, which
# may be ahead of the sdk's.
FROM ${SDK} AS gui
ARG DEBIAN_FRONTEND=noninteractive
COPY --from=freecoredata / /tmp/freecoredata/
RUN set -e; cd /tmp/freecoredata; make clean >/dev/null 2>&1 || true; \
    make -j"$(nproc)" && make install && make -C Tools/momc && make -C Tools/momc install; \
    rm -rf /tmp/freecoredata
# Fonts with italic faces, for the app's text and its tests.
RUN apt-get update && apt-get install -y --no-install-recommends fonts-dejavu-extra && rm -rf /var/lib/apt/lists/*

FROM gui AS build
COPY . /usr/src/topotext
WORKDIR /usr/src/topotext
RUN rm -rf build obj Tests/obj && make -j"$(nproc)" && make install \
 && make -C Examples/SimpleNotes -j"$(nproc)"

FROM build AS check
RUN make test && make -C Examples/SimpleNotes check

FROM build AS sdk
WORKDIR /work
