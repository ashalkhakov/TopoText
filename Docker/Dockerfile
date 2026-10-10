# syntax=docker/dockerfile:1
#
# TopoText and SimpleNotes on GNUstep, built and tested in ODataKit's sdk
# image (the GNUstep stack, FreeCoreData and ODataKit installed; ODataKit's
# Docker/Dockerfile), with gnustep-gui and -back added for the app:
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
FROM alpine/git AS freecoredata-git
ARG FREECOREDATA_REF=524709592bf8670dab363d4c00d70eff4aa51e55
RUN git clone -q https://github.com/ashalkhakov/FreeCoreData.git /src && cd /src && git checkout -q "$FREECOREDATA_REF"
FROM scratch AS freecoredata
COPY --from=freecoredata-git /src /

# The sdk has Foundation only: AppKit (gui, back on cairo) built into its
# prefix by the same script, for SimpleNotes, with the Eau theme the app
# looks as on any of our Linux apps (XFormsKit, RDLKit, ODataKit's); and
# Foundation again, at this pin, which may be ahead of the sdk's.
FROM ${SDK} AS gui
ARG DEBIAN_FRONTEND=noninteractive
ARG GNUSTEP_PATCHES_REF=610d60bfdc18b5d36587e799e1b26c460a608d9d
RUN apt-get update && apt-get install -y --no-install-recommends -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
      libcairo2-dev libjpeg-dev libtiff-dev libpng-dev libicns-dev libfreetype-dev libfontconfig1-dev \
      libxrender-dev libxt-dev libxmu-dev libxft-dev libxrandr-dev libxfixes-dev libxcursor-dev \
      xvfb xauth fonts-dejavu-core \
 && rm -rf /var/lib/apt/lists/*
RUN set -e; \
    mkdir -p /tmp/src/gnustep-patches && cd /tmp/src/gnustep-patches; \
    git init -q && git remote add origin https://github.com/ashalkhakov/gnustep-patches.git; \
    git fetch -q --depth 1 origin "$GNUSTEP_PATCHES_REF" && git checkout -q FETCH_HEAD; \
    PREFIX=/opt/gnustep SOURCES=/tmp/src/gnustep COMPONENTS="libs-base libs-gui libs-back eau" Scripts/build-gnustep.sh; \
    rm -rf /tmp/src
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
