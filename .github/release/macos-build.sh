#!/bin/bash
# The Mac app for gnustep-release-actions' macos-release.yml: SimpleNotes.app
# (universal, its frameworks embedded) into $RELEASE_DIR, and the server its
# self-test runs against, left where Xcode built it, beside the frameworks
# it loads (macos-test.sh). ODataKit is checked out beside this repository.
#
# First what CI ran before the apps: the Xcode projects as Scripts/xcodeproj.py
# writes them, ODataKit, the libraries and their unit tests against Apple's
# Foundation and Core Data, a long convergence run, and SimpleNotes' tests
# with two devices through its server (Makefile.apple).
set -euo pipefail
xcodebuild -version
python3 Scripts/xcodeproj.py
git diff --exit-code -- '*.xcodeproj' '*.xcworkspace' \
  || { echo "::error::run Scripts/xcodeproj.py and commit what it writes"; exit 1; }
make odatakit ODATAKIT=../ODataKit
make
make test
TOPOTEXT_SEEDS=2000 xcrun xctest -XCTest TopoTextFuzzTests,TTTableTests/testCopiesEditedAtRandomConverge build/TopoTextTests.xctest
make -C Examples/SimpleNotes check

for scheme in SimpleNotes simplenotes-server; do
  xcodebuild -workspace TopoText.xcworkspace -scheme "$scheme" \
    -destination 'generic/platform=macOS' -configuration Release \
    -derivedDataPath "$RUNNER_TEMP/DerivedData" build
done
products=$RUNNER_TEMP/DerivedData/Build/Products/Release
for fw in TopoText TopoTextSync ODataKit ODataSync; do
  test -d "$products/SimpleNotes.app/Contents/Frameworks/$fw.framework" \
    || { echo "::error::SimpleNotes.app does not embed $fw.framework"; exit 1; }
done
ditto "$products/SimpleNotes.app" "$RELEASE_DIR/SimpleNotes.app"
