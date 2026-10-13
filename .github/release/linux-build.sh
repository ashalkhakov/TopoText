#!/bin/bash
# On the stack in $PREFIX: TopoText alone (Foundation only, as it is kept),
# then FreeCoreData, ODataKit (beside this repository) and TopoText with
# SimpleNotes, and their tests: the unit tests, SimpleNotes' (two devices
# through its server, the window under Xvfb), and its server on PostgreSQL
# and MariaDB, and moved from SQLite to PostgreSQL (the servers
# gnustep-release-actions starts: databases in build.yml).
set -eo pipefail
# GNUstep.sh reads unset variables (ZSH_VERSION), so set -u comes after it.
. "$PREFIX/System/Library/Makefiles/GNUstep.sh"
set -u
make WITH_SYNC=no
make clean
.github/scripts/build-libraries.sh
test -f "$(gnustep-config --variable=GNUSTEP_LOCAL_HEADERS)/TopoText/TopoText.h"
make test
make -C Examples/SimpleNotes -j"$(nproc)"
make -C Examples/SimpleNotes check

# The server on the databases.
cd Examples/SimpleNotes
SN_STORE_ARGS="-StoreType PostgreSQL -StoreURL $POSTGRES_URL" \
  Tests/serve-and-check.sh ./obj/simplenotes-server ./SimpleNotes.app/SimpleNotes --check
SN_STORE_ARGS="-StoreType MariaDB -StoreURL $MARIADB_URL" SN_CHECK_PORT=18081 \
  Tests/serve-and-check.sh ./obj/simplenotes-server ./SimpleNotes.app/SimpleNotes --check
docker exec "$POSTGRES_CONTAINER" psql -U postgres -c 'CREATE DATABASE moved'
Tests/move-and-check.sh ./obj/simplenotes-server -StoreType PostgreSQL -StoreURL "${POSTGRES_URL%/*}/moved"
