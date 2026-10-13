#!/bin/bash
# The libraries and SimpleNotes with its server into the prefix's System
# domain, where gnustep-release-actions' appimage takes them from; the
# server finds its model beside itself.
set -eo pipefail
# GNUstep.sh reads unset variables (ZSH_VERSION), so set -u comes after it.
. "$PREFIX/System/Library/Makefiles/GNUstep.sh"
set -u
make install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
make -C Examples/SimpleNotes install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
server=$(find "$PREFIX/System/Tools" -type f -name simplenotes-server -perm -111 | head -n 1)
[ -n "$server" ] || { echo "simplenotes-server was not installed" >&2; exit 1; }
rm -rf "$(dirname "$server")/SimpleNotes.momd"
cp -R Examples/SimpleNotes/obj/SimpleNotes.momd "$(dirname "$server")/"
