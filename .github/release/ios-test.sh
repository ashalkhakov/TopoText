#!/bin/bash
# The iOS app's self-test in a simulator, against its own server.
set -euo pipefail
Examples/SimpleNotes/Tests/ios-self-test.sh "$RUNNER_TEMP/Server/Build/Products/Release/simplenotes-server" "$1"
