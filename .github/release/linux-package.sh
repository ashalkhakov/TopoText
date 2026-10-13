#!/bin/bash
# SimpleNotes-<version>-x86_64.AppImage, with its server in it.
set -euo pipefail
GNUSTEP_PREFIX="$PREFIX" ./Scripts/prepare-appdir.sh
GNUSTEP_PREFIX="$PREFIX" ./Scripts/package-appimage.sh
