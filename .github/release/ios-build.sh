#!/bin/bash
# The iOS app, unsigned, for a device and for the simulator, into
# $RELEASE_DIR; and the server its simulator self-test runs against, left
# where Xcode built it, beside its frameworks (ios-test.sh).
set -euo pipefail
xcodebuild -workspace TopoText.xcworkspace -scheme SimpleNotes-iOS \
  -destination 'generic/platform=iOS' -configuration Release \
  -derivedDataPath "$RUNNER_TEMP/DerivedData" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
xcodebuild -workspace TopoText.xcworkspace -scheme SimpleNotes-iOS \
  -destination 'generic/platform=iOS Simulator' -configuration Release \
  -derivedDataPath "$RUNNER_TEMP/DerivedData" build
xcodebuild -workspace TopoText.xcworkspace -scheme simplenotes-server \
  -destination 'platform=macOS' -configuration Release \
  -derivedDataPath "$RUNNER_TEMP/Server" build
products=$RUNNER_TEMP/DerivedData/Build/Products
ditto "$products/Release-iphoneos/SimpleNotes.app" "$RELEASE_DIR/iphoneos/SimpleNotes.app"
ditto "$products/Release-iphonesimulator/SimpleNotes.app" "$RELEASE_DIR/iphonesimulator/SimpleNotes.app"
