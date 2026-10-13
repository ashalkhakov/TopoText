#!/bin/bash
# The iOS app's self-test in a simulator, against its own server.
set -euo pipefail
Examples/SimpleNotes/Tests/ios-self-test.sh "$RELEASE_DIR/simplenotes-server" "$1"
