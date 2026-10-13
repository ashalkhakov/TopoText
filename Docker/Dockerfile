# syntax=docker/dockerfile:1
#
# TopoText and SimpleNotes on GNUstep, built and tested in ODataKit's sdk
# image (the GNUstep stack, FreeCoreData, GCDWebServer and ODataKit
# installed; ODataKit's Docker/Dockerfile), the one its release at
# .github/pins.env's ODATAKIT_VERSION publishes:
#
#   v=$(sed -n 's/^ODATAKIT_VERSION=//p' .github/pins.env)
#   docker build -f Docker/Dockerfile --build-arg ODATAKIT_VERSION=$v --target check .
#   docker build -f Docker/Dockerfile --build-arg ODATAKIT_VERSION=$v --target sdk -t topotext-sdk .
#
# Or on an sdk of one's own (--build-arg SDK=odatakit-sdk, built from a
# checkout of ODataKit).

ARG ODATAKIT_VERSION
ARG SDK=ghcr.io/ashalkhakov/odatakit-sdk:${ODATAKIT_VERSION}

FROM ${SDK} AS gui
ARG DEBIAN_FRONTEND=noninteractive
# Fonts with italic faces, for the app's text and its tests.
RUN apt-get update && apt-get install -y --no-install-recommends fonts-dejavu-extra && rm -rf /var/lib/apt/lists/*

# The libraries, then SimpleNotes and its server.
FROM gui AS build
COPY . /usr/src/topotext
WORKDIR /usr/src/topotext
RUN rm -rf build obj Tests/obj Examples/SimpleNotes/obj && make -j"$(nproc)" && make install

# What needs no database: the unit tests, and SimpleNotes' (two devices
# through its server, the app driven from within).
FROM build AS check
RUN make test && make -C Examples/SimpleNotes check

FROM build AS sdk
WORKDIR /work
