#!/bin/bash
# The app driven from within against its own server (Tests/self-test.sh).
set -euo pipefail
Examples/SimpleNotes/Tests/self-test.sh "$RUNNER_TEMP/DerivedData/Build/Products/Release/simplenotes-server" "$1/Contents/MacOS/SimpleNotes"
