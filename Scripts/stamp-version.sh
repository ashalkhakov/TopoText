#!/bin/bash
# Write a version into what SimpleNotes' About panel reads on GNUstep, so a
# packaged build says which build it is. From XFormsKit's
# Scripts/stamp-version.sh.
#
#   ./Scripts/stamp-version.sh 1.2.3
#
# The version comes from the tag, or from the run number for an unreleased
# build: the same value the AppImage and the macOS archive are named after.
# Xcode's builds take theirs as build settings (MARKETING_VERSION,
# CURRENT_PROJECT_VERSION: release.yml), which AppKit/Info.plist and
# iOS/Info.plist read; GNUstep's app takes it from SimpleNotesInfo.plist,
# which gnustep-make merges into the bundle's Info-gnustep.plist:
# ApplicationRelease and FullVersionID are what GSInfoPanel shows.
set -euo pipefail

version=${1:-}
if [ -z "$version" ]; then
    echo "usage: $0 <version>" >&2
    exit 2
fi
display=${version#v}
root=$(cd "$(dirname "$0")/.." && pwd)

python3 - "$root/Examples/SimpleNotes/SimpleNotesInfo.plist" "$display" <<'PY'
import re, sys
path, display = sys.argv[1:3]
text = open(path).read()
for key in ("ApplicationRelease", "FullVersionID"):
    line = '    %s = "%s";' % (key, display)
    text, n = re.subn(r'^\s*%s = [^;]*;' % key, lambda m: line, text, flags=re.M)
    if n == 0:
        text = text.replace("{\n", "{\n%s\n" % line, 1)
open(path, "w").write(text)
PY

echo "stamped $display"
grep -E "ApplicationRelease|FullVersionID" "$root/Examples/SimpleNotes/SimpleNotesInfo.plist"
