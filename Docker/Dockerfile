# syntax=docker/dockerfile:1
#
# TopoText on GNUstep, built and tested in ODataKit's sdk image (the GNUstep
# stack, FreeCoreData and ODataKit installed; ODataKit's Docker/Dockerfile):
#
#   docker build -f Docker/Dockerfile --target check .
#   docker build -f Docker/Dockerfile --target sdk -t topotext-sdk .
#
# SDK: that image, built from a checkout of ODataKit
#   (docker build -f Docker/Dockerfile --target sdk -t odatakit-sdk . there)
# or as a release publishes it (ghcr.io/ashalkhakov/odatakit-sdk:<version>).

ARG SDK=odatakit-sdk:latest

FROM ${SDK} AS build
COPY . /usr/src/topotext
WORKDIR /usr/src/topotext
RUN rm -rf build obj Tests/obj && make -j"$(nproc)"

FROM build AS check
RUN make test

FROM build AS sdk
RUN make install
WORKDIR /work
