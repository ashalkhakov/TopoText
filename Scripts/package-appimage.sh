#!/bin/bash
# Turn the AppDir into an AppImage. From ODataKit's Scripts/package-appimage.sh
# (after XFormsKit's).
#
#   APP_VERSION=1.2.3 GNUSTEP_PREFIX=... ./Scripts/package-appimage.sh
set -euo pipefail

WORKSPACE_DIR=$(pwd)
LOCAL_PREFIX="${GNUSTEP_PREFIX:-/opt/gnustep-prefix}"
# Where Scripts/install-linuxdeploy.sh puts it.
LINUXDEPLOY="${LINUXDEPLOY:-${LINUXDEPLOY_DIR:-${RUNNER_TEMP:-/tmp}/linuxdeploy}/AppRun}"
arch=$(uname -m)

# What linuxdeploy insists on: a launcher, one desktop entry, its icon.
install -m 0755 Scripts/appimage/AppRun AppDir/AppRun
install -m 0644 Scripts/appimage/simplenotes.desktop AppDir/simplenotes.desktop
mkdir -p AppDir/usr/share/applications AppDir/usr/share/icons/hicolor/256x256/apps
install -m 0644 Scripts/appimage/simplenotes.desktop AppDir/usr/share/applications/simplenotes.desktop
install -m 0644 Examples/SimpleNotes/Icons/SimpleNotes.png AppDir/simplenotes.png
install -m 0644 Examples/SimpleNotes/Icons/SimpleNotes.png AppDir/usr/share/icons/hicolor/256x256/apps/simplenotes.png

# The executables to trace for libraries, found rather than named:
# gnustep-make decides where they land.
EXEC_ARGS=()
for name in SimpleNotes simplenotes-server; do
  binary=$(find AppDir -type f -name "$name" -perm -111 -exec file {} \; 2>/dev/null | awk -F: '/ELF/{print $1; exit}')
  if [ -z "$binary" ]; then
    echo "No $name executable in AppDir" >&2
    exit 1
  fi
  EXEC_ARGS+=(--executable "$binary")
done

# What is loaded at run time rather than linked -- gnustep-gui's backend
# bundle, which needs cairo and the X libraries; FreeCoreData's SQL stores,
# which need libpq and libmariadb -- and the tools GNUstep starts (gpbs,
# gdnc): their libraries too, not the files themselves, which are already in
# place.
DEPS_ARGS=()
while IFS= read -r elf; do
  DEPS_ARGS+=(--deploy-deps-only "$elf")
done < <( { find AppDir/usr/System/Library/Bundles AppDir/usr/Local/Library/Bundles AppDir/usr/System/Tools AppDir/usr/Local/Tools \
                 -type f -perm -111 2>/dev/null; find AppDir/usr -name 'libCD*Store.so*' -type f 2>/dev/null; } \
              | xargs -r file | awk -F: '/ELF/{print $1}')

export OUTPUT="SimpleNotes-${APP_VERSION:-dev}-${arch}.AppImage"
export APPIMAGE_EXTRACT_AND_RUN=1
export NO_VALIDATE=1
# Keep the symbol tables: Objective-C methods are named only in .symtab, which
# linuxdeploy's strip would remove, and a backtrace from a user's crash is
# worth far more with them.
export NO_STRIP="${NO_STRIP:-1}"
export LDAI_RUNTIME_FILE="${LDAI_RUNTIME_FILE:-/tmp/appimage-runtime/runtime-${arch}}"

# Local before System, as GNUstep.sh orders them: a library installed in
# both (FreeCoreData, updated) is the Local one.
LD_LIBRARY_PATH="${LOCAL_PREFIX}/Local/Library/Libraries:${LOCAL_PREFIX}/System/Library/Libraries:${LOCAL_PREFIX}/lib:${WORKSPACE_DIR}/AppDir/usr/lib:${LD_LIBRARY_PATH:-}" \
  "$LINUXDEPLOY" --appdir AppDir "${EXEC_ARGS[@]}" "${DEPS_ARGS[@]}" --output appimage

echo "built $OUTPUT"
