#!/bin/bash
# FreeCoreData, ODataKit (beside this repository) and TopoText with
# SimpleNotes, on the stack in $PREFIX; the version stamped.
set -euo pipefail
.github/scripts/build-libraries.sh
./Scripts/stamp-version.sh "$APP_VERSION"
