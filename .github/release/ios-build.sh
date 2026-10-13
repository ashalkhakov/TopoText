#!/bin/bash
# The iOS app, unsigned, for a device and for the simulator, and the server
# its simulator self-test runs against.
set -euo pipefail
versions=(MARKETING_VERSION="${APP_VERSION%%-*}" CURRENT_PROJECT_VERSION="$BUILD_NUMBER")
xcodebuild -workspace TopoText.xcworkspace -scheme SimpleNotes-iOS \
  -destination 'generic/platform=iOS' -configuration Release \
  -derivedDataPath "$RUNNER_TEMP/Release" "${versions[@]}" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
xcodebuild -workspace TopoText.xcworkspace -scheme SimpleNotes-iOS \
  -destination 'generic/platform=iOS Simulator' -configuration Release \
  -derivedDataPath "$RUNNER_TEMP/Release" "${versions[@]}" build
xcodebuild -workspace TopoText.xcworkspace -scheme simplenotes-server \
  -destination 'platform=macOS' -configuration Release \
  -derivedDataPath "$RUNNER_TEMP/Server" build
products=$RUNNER_TEMP/Release/Build/Products
ditto "$products/Release-iphoneos/SimpleNotes.app" "$RELEASE_DIR/iphoneos/SimpleNotes.app"
ditto "$products/Release-iphonesimulator/SimpleNotes.app" "$RELEASE_DIR/iphonesimulator/SimpleNotes.app"
cp "$RUNNER_TEMP/Server/Build/Products/Release/simplenotes-server" "$RELEASE_DIR/"
