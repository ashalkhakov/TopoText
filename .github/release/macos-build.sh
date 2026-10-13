#!/bin/bash
# The Mac app for gnustep-release-actions' macos-release.yml: SimpleNotes.app
# (universal, its frameworks embedded) into $RELEASE_DIR, and the server its
# self-test runs against, left where Xcode built it, beside the frameworks
# it loads (macos-test.sh). ODataKit is checked out beside this repository.
set -euo pipefail
for scheme in SimpleNotes simplenotes-server; do
  xcodebuild -workspace TopoText.xcworkspace -scheme "$scheme" \
    -destination 'generic/platform=macOS' -configuration Release \
    -derivedDataPath "$RUNNER_TEMP/DerivedData" \
    MARKETING_VERSION="${APP_VERSION%%-*}" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" build
done
products=$RUNNER_TEMP/DerivedData/Build/Products/Release
for fw in TopoText TopoTextSync ODataKit ODataSync; do
  test -d "$products/SimpleNotes.app/Contents/Frameworks/$fw.framework" \
    || { echo "::error::SimpleNotes.app does not embed $fw.framework"; exit 1; }
done
ditto "$products/SimpleNotes.app" "$RELEASE_DIR/SimpleNotes.app"
