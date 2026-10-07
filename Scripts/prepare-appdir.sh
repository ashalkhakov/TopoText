#!/bin/bash
# Assemble the AppDir: SimpleNotes, its server, TopoText, ODataKit,
# FreeCoreData (with its PostgreSQL and MySQL stores) and the GNUstep runtime
# they run on. From ODataKit's Scripts/prepare-appdir.sh (after XFormsKit's,
# RDLKit's and UDQuakeTools').
#
#   GNUSTEP_PREFIX=/path/to/gnustep ./Scripts/prepare-appdir.sh
#
# The prefix has the stack, FreeCoreData and ODataKit installed already
# (.github/scripts/build-linux.sh). The libraries and the app are installed
# into it here, so they sit in the GNUstep layout AppRun points GNUstep at.
set -euo pipefail

LOCAL_PREFIX="${GNUSTEP_PREFIX:-/opt/gnustep-prefix}"

rm -rf AppDir
mkdir -p AppDir/usr/bin AppDir/usr/lib AppDir/usr/etc

set +u  # GNUstep.sh reads variables it has not set
. "${LOCAL_PREFIX}/System/Library/Makefiles/GNUstep.sh"
set -u

make
make install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
make -C Examples/SimpleNotes
make -C Examples/SimpleNotes install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM

# The server finds its model beside itself.
server=$(find "${LOCAL_PREFIX}/System/Tools" -type f -name simplenotes-server -perm -111 | head -n 1)
if [ -z "$server" ]; then
  echo "simplenotes-server was not installed" >&2
  exit 1
fi
rm -rf "$(dirname "$server")/SimpleNotes.momd"
cp -R Examples/SimpleNotes/obj/SimpleNotes.momd "$(dirname "$server")/"

# The prefix's GNUstep hierarchies: the app, the libraries, the backend
# bundle, the tools GNUstep starts (gdnc, gpbs, make_services).
for domain in System Local; do
  if [ -d "${LOCAL_PREFIX}/$domain" ]; then
    mkdir -p "AppDir/usr/$domain"
    cp -Rp "${LOCAL_PREFIX}/$domain/"* "AppDir/usr/$domain/"
  fi
done
# What a GNUstep image does not need at run time.
rm -rf AppDir/usr/System/Library/Headers AppDir/usr/Local/Library/Headers \
       AppDir/usr/System/Library/Makefiles AppDir/usr/System/Library/Documentation

# libobjc2 and libdispatch live in the prefix's plain lib/, outside the
# GNUstep layout.
for lib in "${LOCAL_PREFIX}"/lib/libobjc.so.*.* ; do
  [ -f "$lib" ] || continue
  soname=$(basename "$lib")
  cp -p "$lib" AppDir/usr/lib/
  ln -sf "$soname" "AppDir/usr/lib/${soname%.*}"
  ln -sf "$soname" AppDir/usr/lib/libobjc.so
done
for dir in lib lib64; do
  if ls "${LOCAL_PREFIX}/$dir"/libdispatch.so* >/dev/null 2>&1; then
    cp -p "${LOCAL_PREFIX}/$dir"/libdispatch.so* AppDir/usr/lib/
    cp -p "${LOCAL_PREFIX}/$dir"/libBlocksRuntime.so* AppDir/usr/lib/ 2>/dev/null || true
    break
  fi
done

# The backend bundle under the names gnustep-gui looks for.
backend=$(find AppDir/usr -name "libgnustep-back-*.bundle" 2>/dev/null | head -n 1 || true)
if [ -n "$backend" ]; then
  ln -sfn "$(basename "$backend")" "$(dirname "$backend")/libgnustep-back.bundle"
  ln -sfn "$(basename "$backend")" "$(dirname "$backend")/back.bundle"
fi

# Fonts, so the window lays out the same on a machine that has none.
mkdir -p AppDir/usr/etc/fonts
cp Scripts/appimage/fonts.conf AppDir/usr/etc/fonts/fonts.conf
for dir in /usr/share/fonts/truetype/dejavu /usr/share/fonts/truetype/liberation; do
  if [ -d "$dir" ]; then
    mkdir -p "AppDir/usr/share/fonts/truetype/$(basename "$dir")"
    cp -Rp "$dir"/* "AppDir/usr/share/fonts/truetype/$(basename "$dir")/"
  fi
done

du -sh AppDir
app=$(find AppDir/usr -maxdepth 5 -name "SimpleNotes.app" -type d | head -n 1)
[ -n "$app" ] || { echo "MISSING: SimpleNotes.app" >&2; exit 1; }
echo "  $app"
for f in simplenotes-server SimpleNotes.momd; do
  found=$(find AppDir/usr/System/Tools -name "$f" | head -n 1)
  [ -n "$found" ] || { echo "MISSING: $f" >&2; exit 1; }
  echo "  $found"
done
# The SQL stores the server loads by name (-StoreType PostgreSQL, MySQL).
for store in CDPostgreSQLStore CDMySQLStore; do
  found=$(find AppDir/usr -name "lib$store.so" | head -n 1)
  [ -n "$found" ] || { echo "MISSING: lib$store.so (FreeCoreData's Backends installed?)" >&2; exit 1; }
  echo "  $found"
done
# The theme AppRun selects: without it GNUstep falls back to its own look.
theme=$(find AppDir/usr -maxdepth 5 -name "Eau.theme" -type d | head -n 1)
if [ -z "$theme" ]; then
  echo "MISSING: Eau.theme (is eau in the GNUstep stack's COMPONENTS?)" >&2
  exit 1
fi
echo "  $theme"
