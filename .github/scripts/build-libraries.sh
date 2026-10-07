#!/bin/bash
# FreeCoreData (momc, the PostgreSQL and MySQL stores), ODataKit and
# TopoText, built and installed into a GNUstep prefix whose stack is built
# already (gnustep-patches' build-gnustep.sh), as ci.yml's GNUstep job does
# step by step. For release.yml's AppImage.
#
#   PREFIX=/path/to/prefix .github/scripts/build-libraries.sh
#
# FreeCoreData and ODataKit are checked out beside this repository
# (../FreeCoreData, ../ODataKit), at the commits the workflow pins.
set -euo pipefail

: "${PREFIX:?the GNUstep prefix}"
here=$(cd "$(dirname "$0")/../.." && pwd)
jobs=$(nproc)

set +u  # GNUstep.sh reads variables it has not set
. "$PREFIX/System/Library/Makefiles/GNUstep.sh"
set -u
export LD_LIBRARY_PATH="$PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

cd "$here/../FreeCoreData"
make -j"$jobs" && make install
make -C Tools/momc && make -C Tools/momc install
for backend in PostgreSQL MySQL; do
  make -C "Backends/$backend" && make -C "Backends/$backend" install
done

cd "$here/../ODataKit"
make -j"$jobs" && make install

cd "$here"
make -j"$jobs" && make install
